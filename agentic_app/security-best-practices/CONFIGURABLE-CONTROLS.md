# Controls you switch on

Security controls MDAA exposes as config properties — you get them by setting a property, not by doing anything out of band. **Nothing here is a prerequisite**; it all happens inside your module config.

This is a map, not a description. The authoritative reference is [SCHEMA.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-agentcore-runtime-app/SCHEMA.md), which is generated from the code, and the runtime config files carry the reasoning inline — why each value, and what breaks if you change it. Read those rather than a summary of them.

## The config is layered, and the layer is the difference

The runtime config is assembled from a base plus exactly one inbound-auth layer, merged left to right by MDAA. The base holds everything both paths share; the layer holds only what that path changes — so to see the difference between the two, read a layer rather than diffing two long files.

| File | Role |
| --- | --- |
| [`../bedrock-agentcore-runtime/runtime-base.yaml`](../bedrock-agentcore-runtime/runtime-base.yaml) | Everything shared. Not deployable alone |
| [`../bedrock-agentcore-runtime/runtime-jwt.yaml`](../bedrock-agentcore-runtime/runtime-jwt.yaml) | Cognito JWT / OAuth inbound — **what `mdaa.yaml` deploys** |
| [`../bedrock-agentcore-runtime/runtime-sigv4.yaml`](../bedrock-agentcore-runtime/runtime-sigv4.yaml) | SigV4 (IAM) inbound — swap in to use it |

**Why the base carries no authorizer.** Omitting `authorizerConfiguration` is what selects SigV4, and a merge layer can add settings but never remove them — so the absence has to live in the base and the JWT layer adds it back. That is also why the two layers are not interchangeable in the other direction.

| | JWT / OAuth | SigV4 (IAM) |
| --- | --- | --- |
| `authorizerConfiguration` | `customJwtAuthorizer.cognito` — added by the layer | **absent** — inherited from the base |
| `endpointPolicy.allowPrincipals` | **must stay unset** — OAuth callers have no IAM identity to match, so naming principals denies everyone | **set** to the operator role; MDAA warns at synth if a SigV4 runtime leaves it unset |
| Caller IAM roles | none exist to scope | Admin / Operator / Reader in [`../roles/roles-callers.yaml`](../roles/roles-callers.yaml) |
| What `enforceVpcOnly` is doing | **the entire perimeter** — no SCP or endpoint policy reaches an OAuth caller | defence in depth; SCPs already reach callers |
| Why `vpcEndpoint` is set | **mandatory** — `aws:SourceVpc` only exists for requests through an endpoint, so without one nothing can invoke | one layer of several |
| `auth-failure` alerting catches | resource-policy denials only — the authorizer refuses bad tokens before IAM is consulted | IAM authorization failures, attributable to a named role |

## Control → property

| Control | Property | Set in |
| --- | --- | --- |
| VPC-only invocation, enforced per resource | `enforceVpcOnly` | both |
| Private invocation path | `networkConfiguration.vpcEndpoint` | both |
| No-NAT supporting endpoints | `…vpcEndpoint.createSupportingEndpoints` | commented in both |
| Endpoint policy principals | `…endpointPolicy.allowPrincipals` | SigV4 only — see above |
| JWT inbound auth | `authorizerConfiguration.customJwtAuthorizer` | JWT only |
| Token lifetime | `cognito.idTokenValidityMinutes` (default 15, range 5–60) | JWT |
| MFA | `cognito.mfa` (default `required`) | JWT |
| Pool retention | `cognito.removalPolicy` (default `retain`) | JWT |
| Hosted sign-in | `cognito.hostedUi` | JWT |
| Model scoping | `allowedModelArns` | both |
| Extra PII identifiers | `dataProtection.additionalIdentifiers` | both |
| Log retention | `logRetentionDays` | both |
| Trace search | `enableTransactionSearch` (singleton per account/Region) | commented in both |
| Alarms | `alarms`, with `notificationEmails` | both |
| Security event rules | `eventBridgeAlerts` | both |
| Invocation audit trail | `dataEventSelectors` (`audit-trail` module) | [`../audit-trail/audit-trail.yaml`](../audit-trail/audit-trail.yaml) |
| Log read without unmasking | `generatePolicies` (`roles` module) | [`../roles/roles.yaml`](../roles/roles.yaml) |
| Caller privilege separation | `generateRoles` (`roles` module) | [`../roles/roles-callers.yaml`](../roles/roles-callers.yaml) |
| Gateway error verbosity | `exceptionLevel` — leave unset in production | not demonstrated; needs a `bedrock-builder` config |

## Two things the configs get right by leaving something out

Worth knowing, because both look like omissions:

- **`allowedAudience` is absent from the JWT config.** MDAA populates it with the app client it creates. Setting `allowedClients` alongside it is rejected at synth — Cognito puts the client ID in the ID token's `aud` but the access token's `client_id`, so configuring both filters denies every caller.
- **`policies` is commented out in both.** The execution role needs nothing beyond what MDAA grants it, and the execution role is the blast radius boundary — any code in the microVM can read its credentials from the metadata service, including code the model generates.

## Where the boundary is

- Something you set in a config file → here
- Something MDAA does whether you ask or not → [BUILT-IN-CONTROLS.md](BUILT-IN-CONTROLS.md)
- Something outside the config, in another account, or owned by another team → [YOUR-RESPONSIBILITIES.md](YOUR-RESPONSIBILITIES.md)
