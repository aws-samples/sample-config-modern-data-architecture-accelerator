# What you have to do

Organization- and account-level AWS controls for Amazon Bedrock AgentCore that **no workload deployment can establish for itself**. Everything here is out of band: it happens outside the MDAA config, usually in a different account or by a different team.

MDAA's [SECURITY.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/SECURITY.md) assumes it is "deployed into an AWS Organization/Account/VPC topology which meets the organization's security control requirements" and inherits that topology's controls. This document is what those controls are for AgentCore.

**Nothing MDAA does for you appears here.** For that, see [BUILT-IN-CONTROLS.md](BUILT-IN-CONTROLS.md) (what you get unconditionally) and [CONFIGURABLE-CONTROLS.md](CONFIGURABLE-CONTROLS.md) (what you get by setting a property, and which sample config demonstrates it).

Applies to **AgentCore Runtime** and **AgentCore Gateway** (via [bedrock-builder](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-builder-app/README.md)'s `gateways`). Items are marked (Runtime) or (Gateway) where they differ.

| Section | What it covers |
| --- | --- |
| [1. Checklist](#1-checklist) | Everything on you, grouped by who you need to talk to |
| [2. SCP guardrails](#2-scp-guardrails) | Ready-to-apply policies, where to attach each, and how to test |
| [3. CloudTrail data events](#3-cloudtrail-data-events) | Why invocation is unaudited by default |
| [4. Evaluation order](#4-evaluation-order) | Which layer stops which caller |
| [5. Containment and incident response](#5-containment-and-incident-response) | How to stop a misbehaving agent, and what to write down first |
| [6. Cross-account observability](#6-cross-account-observability-oam) | Only if agents span accounts |
| [7. Applying the prerequisites](#7-applying-the-prerequisites) | LZA, scripted, or console |

---

## 1. Checklist

### Needs organization-admin authority

Without it these are a conversation with whoever owns your AWS Organization, not a task you can finish.

- [ ] SCP enforces VPC-only creation — [the baseline SCP](#2-scp-guardrails)
- [ ] SCP blocks non-VPC invocation — [the baseline SCP](#2-scp-guardrails)
- [ ] The remaining guardrails reviewed and attached by OU — [section 2](#2-scp-guardrails) groups them by blast radius
- [ ] Every Deny you intend to rely on tested in a sandbox OU first — [Test before you attach](#test-before-you-attach). This is the step that decides whether any of the above enforce anything

### Needs the team that owns the VPC

- [ ] Runtime subnets are **private**. A public subnet gives AgentCore Runtime no egress at all
- [ ] Egress decided deliberately: a NAT route, or VPC endpoints only. Endpoints-only is the tighter posture where the agent calls nothing outside AWS — it also removes the arbitrary outbound path a compromised agent would otherwise use to exfiltrate
- [ ] A `bedrock-agentcore` interface endpoint exists in the VPC. MDAA can create it, but only one endpoint per service per VPC may have Private DNS — so if a central networking team or LZA already owns one, that ownership has to be agreed rather than assumed. See [`lza/README.md`](../lza/README.md), where this is the most likely real-world collision
- [ ] VPC Flow Logs enabled on the runtime's subnets
- [ ] Decide whether callers reach the runtime **directly or through a front door of your own**. Rate limiting, IP filtering, and request size limits need an API Gateway or ALB in front, with WAF attached to that — the AgentCore endpoint is AWS-managed, so nothing can be attached to it directly. Without a front door there is no throttle between a caller and per-invocation model spend. Note the consequence for authorization: when a gateway fronts a SigV4 runtime, the gateway's execution role becomes the caller, which is incompatible with [`jwt-inbound-auth.json`](#per-policy-caveats)
- [ ] **Regulated workloads:** clients target the FIPS endpoints. This affects both SDK configuration on the calling side and the service name of the interface endpoint, so confirm a FIPS variant exists for `bedrock-agentcore` in your Region before designing around it

### Needs the team that owns your identity provider

- [ ] Allowed scopes and required custom claims configured on the JWT authorizer. AWS recommends setting "all available validation fields: discovery URL, allowed audiences, allowed clients, allowed scopes, and required custom claims." MDAA covers discovery, audience, and clients; check the current [SCHEMA.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-agentcore-runtime-app/SCHEMA.md) for the rest before assuming it is still outstanding
- [ ] Access-token lifetime set to 15–30 minutes on the `discoveryUrl` path (on the `cognito` path MDAA sets it). **Know why before you tune it:** JWT validation is offline, so there is no way to revoke an individual token — see [section 5](#5-containment-and-incident-response). A shorter lifetime narrows that gap but also caps how long a single agent invocation can run
- [ ] IdP signing-key rotation procedure documented and tested — it is the only mechanism that revokes everything, and the one you least want to improvise

### Needs someone with IAM authority in the account

- [ ] **If you supply your own execution role via `roleArn`**, four things MDAA would otherwise write become yours: the `aws:SourceAccount` and `ArnLike`-on-`aws:SourceArn` confused-deputy conditions in the trust policy, `logs:PutResourcePolicy` scoped to this agent's own log groups, and the observability and model-invocation permissions. MDAA returns a bare reference and cannot modify a role it did not create
- [ ] Execution role has **equal or fewer privileges than the callers who can invoke it**. Any code in the microVM can read the role's credentials from the metadata service — including code the model generates — so the execution role is the blast radius boundary, and a role more privileged than its invokers is a privilege-escalation path
- [ ] `logs:Unmask` denied to principals with no business bypassing PII masking. MDAA applies the Data Protection policy, but masking only holds for callers *without* that action. Worked example: [`../roles/roles.yaml`](../roles/roles.yaml)
- [ ] Caller roles separated by privilege — Admin for lifecycle, Operator for invoke, Reader for inspection, each scoped to specific runtime ARNs. **SigV4 inbound only:** OAuth callers are not IAM principals, so there is nothing to scope. Worked example: [`../roles/roles-callers.yaml`](../roles/roles-callers.yaml)
- [ ] `InvokeAgentRuntimeForUser` and `GetWorkloadAccessTokenForUserId` explicitly denied where user-id delegation is not needed, so all user identification goes through the verified token path rather than a caller-supplied parameter
- [ ] `bedrock-agentcore:InboundJwtClaim/*` conditions applied to whichever principal performs token exchange, **once the agent fetches outbound credentials through AgentCore Identity**. Not applicable to an agent that only calls Bedrock — see the commented block in [`../roles/roles.yaml`](../roles/roles.yaml) for why, and when that changes
- [ ] Execution roles audited periodically with IAM Access Analyzer

### Needs the team that owns audit and monitoring

- [ ] CloudTrail **data** events enabled for AgentCore. **The trail may not be yours** — if a central security team owns it, this is a request you file, not a property you set. Without it there is no record of who invoked which agent, and the `auth-failure` alerting deploys clean and never fires. See [section 3](#3-cloudtrail-data-events)
- [ ] X-Ray Transaction Search owned by exactly one deployment per account per Region. It is a singleton, so every other AgentCore deployment in the account must opt out or its stack fails — a coordination question, not a config choice
- [ ] Alarm notification subscriptions **confirmed**. SNS will not deliver until the recipient accepts the confirmation request, and MDAA cannot do that for you. Until then alarms evaluate normally and notify nobody
- [ ] No PII in identifiers. The JWT `Subject` claim is written to CloudTrail; gateway, target, and tool names are not encrypted; tags are free text. Cognito's `sub` is an opaque UUID, so the `cognito` path is safe here — a `discoveryUrl` IdP that puts an email in `sub` is not
- [ ] Tamper-resistant retention for the trail — S3 Object Lock, if invocation records are evidence
- [ ] Cross-account observability configured if agents span accounts — [section 6](#6-cross-account-observability-oam)

### Needs an operations owner

- [ ] A containment runbook exists, tested — [section 5](#5-containment-and-incident-response)

### Not in this document

Four obligations are the application's rather than the platform's, and live with the code they constrain:

| Obligation | Where |
| --- | --- |
| User-to-session binding — AgentCore does not verify that a caller owns the session it names | Runtime module README |
| Container runs as a non-root **numeric** UID | [`../bedrock-agentcore-runtime/agent_core_code/Dockerfile`](../bedrock-agentcore-runtime/agent_core_code/Dockerfile) |
| `aws-opentelemetry-distro>=0.18.0` in the image, or spans silently leave the protected log group | `pyproject.toml` in the same directory |
| Do not set `OTEL_*` or `AGENT_OBSERVABILITY_ENABLED` | [`../bedrock-agentcore-runtime/runtime-jwt.yaml`](../bedrock-agentcore-runtime/runtime-jwt.yaml) |

**Also not on the list: MMDSv2.** AgentCore has required it since 2026-06-30 and enables it by default on runtimes created since, so a new deployment has nothing to do. Only a runtime created **before** that date and never updated needs `metadataConfiguration.requireMMDSV2` set, which is an `update-agent-runtime` call — neither `CreateAgentRuntime` nor CDK's `CfnRuntime` accepts the field. If invocations fail on such a runtime, see the module's TROUBLESHOOTING guide for the failure signature.

### AgentCore services this does not cover

MDAA deploys **Runtime** and **Gateway**. AgentCore has five more services, each with its own security surface, and none of them appears in this checklist — there is no MDAA config, no policy, and no obligation until you deploy one. If you are enabling any of these outside MDAA, the guidance is not here yet.

| Service | The control that matters most, and why it is not obvious |
| --- | --- |
| **Code Interpreter / Browser** | Choice of network mode — Public, Sandbox, or VPC. Credentials stay readable from the microVM metadata service in *all three*, so network mode does not contain what the execution role can reach. Sandbox also leaves DNS open, which is a narrow egress channel |
| **Memory** | Isolation depends on an `actorId` **you supply**. The service never checks it against a real identity, so a wrong value silently reads another user's memory |
| **Policy** | Cedar tool authorization, evaluated outside the model's reasoning loop. Start in `LOG_ONLY`, never straight to `ENFORCE` |
| **Evaluations** | The only detective control for agent *behaviour* — prompt injection, tool misuse, safety regression between versions. Everything else here is preventive |
| **Identity (outbound)** | Third-party credentials via the Token Vault rather than a long-lived secret. Prefer delegation over impersonation, and session-binding on the OAuth consent flow is required, not optional |

Tracked for MDAA support, each carrying the full guidance from the AWS enablement material: [#1378](https://code.aws.dev/proserve/mdaa/modern-data-architecture-accelerator/-/work_items/1378) Tools · [#1379](https://code.aws.dev/proserve/mdaa/modern-data-architecture-accelerator/-/work_items/1379) Memory · [#1380](https://code.aws.dev/proserve/mdaa/modern-data-architecture-accelerator/-/work_items/1380) Policy · [#1381](https://code.aws.dev/proserve/mdaa/modern-data-architecture-accelerator/-/work_items/1381) Evaluations · [#1382](https://code.aws.dev/proserve/mdaa/modern-data-architecture-accelerator/-/work_items/1382) Identity outbound.

Two guardrails already anticipate services MDAA does not deploy: `agentcore-baseline.json` denies `CreateCodeInterpreter` and `CreateBrowser` without VPC configuration, and `cmk-encryption.json` requires a customer-managed key on `CreateMemory`. Both are in [`policies/`](policies/) and attachable today.

### Gateway carries more than Runtime

A Gateway deployment has to do by hand what the Runtime module does for you:

| Control | Gateway |
| --- | --- |
| VPC-only resource policy | Attach the policy directly to the gateway ARN |
| CloudWatch alarms | Create against the gateway's metrics |
| EventBridge security rules | Create rules on the gateway's CloudTrail events |
| PII masking on logs | Apply a Data Protection policy to the delivery group |

> **Check this against the current schema before relying on it.** This describes work you do yourself, which is exactly the kind of claim that goes stale when a module gains a property. Confirm against the [bedrock-builder SCHEMA.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-builder-app/SCHEMA.md) — if a property now exists, use it and treat this table as out of date.

---

## 2. SCP Guardrails

Policy documents are in [`policies/service-control-policies/`](policies/service-control-policies/) and are portable unchanged across LZA, scripted, and console application. Attach them by group rather than all at once — the groups are ordered by blast radius.

| Group | Policy file | Enforces | Attach to |
| --- | --- | --- | --- |
| **Baseline** | [`agentcore-baseline.json`](policies/service-control-policies/agentcore-baseline.json) | VPC-only creation, VPCE-only invocation, Region lockdown, mandatory tag | Every OU running AgentCore |
| Regulated | [`approved-subnets.json`](policies/service-control-policies/approved-subnets.json) | Runtimes only in an approved subnet/SG list | Production OUs, once the list is settled |
| Regulated | [`cmk-encryption.json`](policies/service-control-policies/cmk-encryption.json) | Gateways and Memory require a customer-managed key | Production OUs |
| Regulated | [`gateway-target-types.json`](policies/service-control-policies/gateway-target-types.json) | Blocks arbitrary MCP server URLs and non-IAM credentials | Production OUs running Gateway |
| Regulated | [`org-owned-vpc-endpoints.json`](policies/service-control-policies/org-owned-vpc-endpoints.json) | Invocation only through org-owned endpoints | Production OUs — see the caveat below |
| Conditional | [`jwt-inbound-auth.json`](policies/service-control-policies/jwt-inbound-auth.json) | Authorizer must be `CUSTOM_JWT` | Only OUs where JWT inbound is mandated |
| Not approved | [`deny-all-agentcore.json`](policies/service-control-policies/deny-all-agentcore.json) | Blanket deny on `bedrock-agentcore:*` | OUs where AgentCore is not approved |
| Per resource | [`runtime-vpc-only-invocation.json`](policies/resource-policies/runtime-vpc-only-invocation.json) | VPC-only invocation for OAuth callers | Each JWT-authorized runtime. In MDAA this comes from `enforceVpcOnly` |

**Quotas:** 10 SCPs may be attached directly per OU, and **policies inherited from a parent OU do not count** against that. An SCP document is capped at 10,240 characters, and whitespace counts when saved via CLI or SDK. The baseline merges four guardrails into one document for reviewability, not because of a quota.

**VPC Lattice needs a policy of your own — there is none in `policies/`.** Gateway and Identity both use VPC Lattice underneath, so restrict who may create service-network associations to the AgentCore service-linked role. Two things to get right: there is no single `CreateServiceNetworkAssociation` action, so list all four (`CreateServiceNetworkServiceAssociation`, `CreateServiceNetworkVpcAssociation`, `CreateServiceNetworkResourceAssociation`, `CreateServiceNetworkVpcEndpointAssociation`), and use `ArnNotLike` on `aws:PrincipalARN` rather than `StringNotLike`.

### Test before you attach

**Syntax validation is not enough.** A policy with a condition key the service does not populate deploys cleanly, validates cleanly, and **denies nothing** — a control that appears to exist and does not. Four of the keys used here are real but **undocumented by AWS**, so their per-action behaviour is unestablished — `bedrock-agentcore:RuntimeAuthorizerType` and `KmsKeyArn` on `CreateMemory` (in `jwt-inbound-auth.json` and `cmk-encryption.json`), `namespace` (`cmk-encryption.json`), and whether `aws:VpceOrgID` populates for `bedrock-agentcore` at all (`org-owned-vpc-endpoints.json`). Those three files are the ones to test hardest.

For each Deny you intend to rely on, in a **sandbox OU** first: one call that should be denied, one that should succeed, and one AWS-service-initiated call where an `aws:ViaAWSService` exemption is present. Never attach to the organization root before that. Editing a policy file? See [the policies README](policies/README.md) — four constructs in them look redundant and are not.

### Per-policy caveats

- **`agentcore-baseline.json` — the tag key is `mdaa_env`, not `Environment`.** MDAA emits `mdaa_org`, `mdaa_env`, `mdaa_domain`, `mdaa_cdk_app`, and `mdaa_module_name`. An SCP requiring `aws:RequestTag/Environment` **denies every MDAA AgentCore deployment.** Either key the policy on a tag MDAA emits, or add `Environment` via `tag_configs` first.
- **`jwt-inbound-auth.json` is incompatible with a Gateway-fronted SigV4 runtime.** AWS documents fronting a runtime with a gateway and restricting invocation to the gateway's execution role, which requires IAM inbound auth. This policy denies that architecture. Attach only where JWT inbound is the intended posture.
- **`cmk-encryption.json` covers Memory, which MDAA does not deploy.** Included because Memory is the AgentCore service most likely to hold durable PII, so the guardrail is worth having before anyone enables it.
- **`agentcore-baseline.json` also denies `CreateCodeInterpreter` and `CreateBrowser` without VPC configuration**, for services MDAA does not deploy either. Same reasoning: Code Interpreter executes arbitrary code and Browser reaches external sites, both under an execution role whose credentials any code in the session can read. Either is a route to your data that needs no runtime at all, so leaving them outside the VPC requirement would leave the guardrail with a hole in it.

---

## 3. CloudTrail Data Events

**`InvokeAgentRuntime` is a data event and data events are off by default.** CloudTrail's default is management events, which record resource CRUD (`CreateAgentRuntime`, `UpdateAgentRuntime`, `DeleteAgentRuntime`). Without data events you have no record of who invoked which agent, when, from where, or whether the call was denied.

Two consequences beyond the missing audit trail:

- **The Runtime module's `auth-failure` EventBridge rule never fires.** It matches an invocation data event. The rule deploys cleanly and reports healthy, which is why this is easy to miss. The `config-change` rule matches management events and works as soon as any trail exists.
- **Cross-account dashboards show nothing**, since aggregation only surfaces what source accounts emit.

### What has to be true

A trail in the account and Region must log data events for `AWS::BedrockAgentCore::Runtime`, and `AWS::BedrockAgentCore::RuntimeEndpoint` if you want endpoint-level records. Two CloudTrail properties shape any implementation:

- **One `resources.type` per selector**, so Runtime and RuntimeEndpoint are separate entries. Scope by ARN prefix — `resources.ARN` matches with `StartsWith` and a runtime ARN prefixes its own endpoints, so one prefix covers both.
- **Advanced event selectors replace the trail's defaults.** A trail carrying only data selectors logs **no management events at all**. Keep management events on the same trail or move them elsewhere, or enabling invocation logging silently stops the lifecycle APIs being logged.

### How to satisfy it

**If the trail is yours**, MDAA can deploy it: the `audit-trail` module's [`dataEventSelectors`](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/governance/audit-trail-app/README.md#data-event-selectors) renders the selectors declaratively, and [`../audit-trail/audit-trail.yaml`](../audit-trail/audit-trail.yaml) is a worked example.

**If it is not**, this becomes a request to whoever owns it. Ask for advanced event selectors on the two resource types, scoped by ARN prefix to your runtimes, with management events preserved on that trail. Those three points are what matters; the tool does not.

**Cost.** Data events are billed per event and agent invocation volume can be high. Scope with `resourceArns` rather than capturing a whole resource type, or use a separate trail so invocation records can age out faster than management events. See [CloudTrail pricing](https://aws.amazon.com/cloudtrail/pricing/).

---

## 4. Evaluation Order

An inbound invocation passes five layers, and every one must permit the call.

| Layer | Mechanism | Reaches IAM callers | Reaches OAuth/JWT callers |
| --- | --- | --- | --- |
| 1 | Service control policy | Yes | **No** |
| 2 | VPC endpoint + endpoint policy | Yes | Network path yes; endpoint policy principals **no** |
| 3 | IAM identity-based policy | Yes | **No** — none exists |
| 4 | Resource-based policy | Yes | **Yes** |
| 5 | JWT authorizer | N/A | Yes |

Read column four as the design constraint: for an OAuth-authorized runtime, layers 1 and 3 are absent and layer 2 restricts only the network path. **Layer 4 is doing nearly all the work**, which is why the resource policy is effectively mandatory rather than advisory.

**Resource control policies are not a substitute.** RCPs cap permissions on resources rather than principals, so they would reach OAuth callers — but [they apply only to an explicit list of services](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html#rcp-supported-services) and `bedrock-agentcore` is not on it, and they never apply to service-linked roles, of which AgentCore uses several. Worth re-checking on review; the list grows.

Two rules govern the whole picture:

- **Explicit deny always wins**, across identity-based and resource-based policies alike.
- **Hierarchical authorization** — invoke operations evaluate policies on **both the runtime and the endpoint**, and both must allow.

---

## 5. Containment and Incident Response

Everything above is preventive. This section is what you do when prevention has already failed and an agent is behaving in a way you need to stop **now**. Write it into a runbook before you need it — mid-incident is the wrong time to discover which of these exist.

**Start from the constraint that shapes all of it: there is no way to revoke a single token.** JWT validation is offline — AgentCore caches your IdP's JWKS and verifies signatures locally, with no per-request callback. So disabling a user or client in your identity provider **does not invalidate tokens already issued**; they remain valid until `exp`. The smallest unit of revocation available is a user+agent pair, or an agent's IAM role. Plan around that rather than discovering it under pressure.

### The seven mechanisms, surgical first

| # | Mechanism | Scope | Reach for it when |
| --- | --- | --- | --- |
| 1 | **IAM / SCP Deny** on `bedrock-agentcore:InvokeAgentRuntime*` | A role, an account, or an OU | **Always the first response.** Immediate, reversible, and attributable |
| 2 | **Remove the invocation path** — `DeleteAgentRuntimeEndpoint`, or `UpdateAgentRuntime` to an authorizer that admits no callers | One runtime | You need the agent unreachable regardless of caller identity |
| 3 | **Cut egress** — modify the security group or VPC routing | One runtime's network | The agent itself is the problem and you need it isolated from its targets |
| 4 | **`StopRuntimeSession`** | One session, by `runtimeSessionId` | One session is misbehaving and the others are fine |
| 5 | **`forceAuthentication: true`** on `GetResourceOauth2Token` | One user+agent pair's stored tokens | Outbound credentials for a specific user may be compromised |
| 6 | **Shorten token lifetime** at the IdP (preventive) | Every future token | Before an incident, to narrow the revocation gap |
| 7 | **Rotate IdP signing keys** (break glass) | **Every token from that IdP** | Last resort, and only with evidence the signing key is compromised |

Four things about that table are easy to get wrong:

- **There is no "disable runtime" action.** AgentCore enablement material sometimes refers to one. It does not exist — neither `bedrock-agentcore` nor `bedrock-agentcore-control` has any `Disable*`/`Enable*` operation, and `UpdateAgentRuntime` exposes no enable/disable field. Mechanism 2 is the real form of that intent.
- **Mechanism 1 does not reach OAuth callers.** An SCP restricts IAM principals only, so on a JWT-authorized runtime your first response has to be mechanism 2 or 3 instead. This is the same asymmetry as [section 4](#4-evaluation-order), and it is worth knowing *before* an incident which inbound mode each of your runtimes uses.
- **Mechanism 6 caps how long an agent can run.** An invocation is bounded by `min(inbound token remaining TTL, workload access token TTL)`, so shortening the inbound token shortens maximum agent run time. On the `cognito` path that knob is `cognito.idTokenValidityMinutes`; the workload access token half is fixed by the service. Do not tighten this during an incident without knowing what it does to in-flight work.
- **Mechanism 7 causes a re-authentication surge** across every user and agent on that IdP. Test the procedure before you need it, and know who gets paged when everyone is signed out at once.

### What to write down now

- Which mechanism is first for each runtime, given its inbound auth mode
- Who holds the permissions to execute mechanisms 1–5, and how they get them out of hours
- The IdP key-rotation procedure, tested at least once
- That `StopRuntimeSession` exists and who can call it — it is the only per-session control, and the one operators most often do not know about

---

## 6. Cross-Account Observability (OAM)

Only relevant if agents run in more than one account: a compromised agent goes undetected if its telemetry is never aggregated. **OAM** is the service behind CloudWatch cross-account observability — a **sink** in the monitoring account, an **observability link** in each source account. Sinks are managed by the monitoring account, links by the source account. Full setup is in the [AWS documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account-Setup.html); what follows is what bites.

⚠️ **Download the link template before linking your first source account.** In the monitoring account: Settings → Monitoring account configuration → **Resources to link accounts** → **AWS organization** → **Download CloudFormation template**. CloudWatch generates it pre-filled with this account's configuration ARN, and it creates the link in each source account. **Once the first source account is linked it is no longer downloadable**, and AWS labels the step "(Optional)" — so it is easy to skip and then lose. For an org-wide rollout it is the only mechanism; the alternative URL works for individual accounts only. Deploy it as a StackSet from the management account.

- **Telemetry-type asymmetry is directional.** If the **source** selects more types than the monitoring account allows, **link creation fails and nothing is shared**. The reverse succeeds and shares the intersection. Configure the monitoring account permissively and let each source narrow it.
- **Single Region**, so a multi-Region estate needs a monitoring account per Region. One sink per account per Region; 100,000 source accounts per monitoring account; 5 monitoring accounts per source.
- **An empty console right after setup is expected** — a metric appears only once it emits new datapoints after the link exists.
- **Removal is from the source account**, and a sink cannot be deleted until all its links are gone.
- **Review link permissions periodically** and revoke stale source accounts; a link outlives the reason it was created.

**A sink is unusable without a sink policy**, and the policy uses `Principal: "*"` with an organization condition doing the restriction — so that condition is load-bearing. [`oam-sink-policy.json`](policies/resource-policies/oam-sink-policy.json) scopes by `aws:PrincipalOrgID` and constrains `oam:ResourceTypes` to metrics, log groups, and X-Ray traces. Never leave a sink open: agent spans carry prompts, model outputs, and tool arguments, and the resource-type constraint is what stops a source account sharing them. On the monitoring account, read access needs only `oam:Get*` / `oam:List*` — grant that, not administrator.

**Apply CloudWatch Data Protection in both accounts.** AWS states cross-account observability *shares* rather than copies data, which suggests the source policy still governs — but also that "the first trace copy is free," implying traces are copied, and this module's spans are delivered as traces. Both sides is cheap and correct either way; MDAA covers the source side unconditionally. Note the pricing consequence: logs and metrics carry no additional charge, but **a second trace copy is billable**.

---

## 7. Applying the Prerequisites

**LZA is not required.** These are org-level AWS controls and any mechanism that produces them satisfies the prerequisites. If you run AWS Organizations without LZA, MDAA's AgentCore modules are fully within reach.

| Approach | When it fits | Trade-off |
| --- | --- | --- |
| **Landing Zone Accelerator** | Already running LZA, or wanting the controls in version control with pipeline-enforced drift correction | Declarative, schema-validated before deploy, re-applied every run. Highest setup cost if not already deployed. See [`lza/`](../lza/) |
| **Scripted** (`aws organizations create-policy` / `attach-policy`) | Have Organizations but not LZA | Repeatable and reviewable; no drift detection unless you build it |
| **Console** | Evaluation, a sandbox OU, or a small org | Fastest to try. Not reproducible, and drift is invisible |

The JSON in [`policies/`](policies/) is the portable part — identical across all three. Only the wrapper differs.

For LZA, [`lza/README.md`](../lza/README.md) covers where each policy goes, the `bedrock-agentcore` endpoint, two collisions worth knowing about, and the one control LZA cannot express.

---

## References

- [Security best practices for AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html)
- [Use IAM condition keys with AgentCore VPC settings](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-vpc-condition.html)
- [Use IAM condition keys with AgentCore Gateway](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-gateway-condition-keys.html)
- [How AgentCore works with IAM](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security_iam_service-with-iam.html)
- [Resource-based policies for AgentCore](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/resource-based-policies.html)
- [Service Authorization Reference — Amazon Bedrock AgentCore](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonbedrockagentcore.html)
- [Resource control policies (RCPs)](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_rcps.html)
- [AWS Organizations quotas](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_reference_limits.html)
- [AWS global condition context keys](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html)
- [CloudWatch cross-account observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html)
- [Landing Zone Accelerator on AWS](https://github.com/awslabs/landing-zone-accelerator-on-aws) — fragments written against v1.16.0
- [LZA Universal Configuration](https://github.com/aws/lza-universal-configuration)
- MDAA [SECURITY.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/SECURITY.md), [CONFIGURATION.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/CONFIGURATION.md), and the AgentCore Runtime module [README](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-agentcore-runtime-app/README.md)
