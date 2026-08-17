# AgentCore security prerequisite policies

Policy documents referenced by [YOUR-RESPONSIBILITIES.md](../YOUR-RESPONSIBILITIES.md). They are portable unchanged across LZA, scripted, and console application — see that document for what each one enforces and where to attach it.

**Deploying them unmodified?** You do not need this file. Read it before **editing** one.

---

## Before you edit these files

Three of them carry site-specific values you must substitute: `approved-subnets.json` (subnet and security-group IDs), and in `agentcore-baseline.json` the Region list and the required tag key. The rest work as shipped.

Four constructs below look redundant and are not. Each produces a policy that deploys cleanly, validates cleanly, and **enforces nothing** if you simplify it.

### Deny on either VPC key, not both

Multiple keys inside one `Null` block are ANDed, so a combined form denies only when subnets *and* security groups are both absent — a request supplying subnets but no security groups passes straight through. Two separate statements is the strict form:

```json
{ "Condition": { "Null": { "bedrock-agentcore:subnets": "true" } } }
{ "Condition": { "Null": { "bedrock-agentcore:securityGroups": "true" } } }
```

Note the [AWS documentation example](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-vpc-condition.html) shows the combined single-statement form. The two-statement form here is deliberately stricter.

### `Bool` on SCPs, `BoolIfExists` on resource policies

SigV4 callers always carry `aws:ViaAWSService`, so plain `Bool` evaluates. OAuth callers do not carry it at all, so on a resource policy plain `Bool` fails to evaluate and the Deny never fires. Reversing these two produces a policy that reads correctly and enforces nothing.

### A resource policy needs both Denies

`StringNotEquals` fires only when the key exists with a wrong value. A caller with no `aws:SourceVpc` — an OAuth call from the internet, never touching a VPC endpoint — leaves the key absent, so the condition cannot evaluate and the call goes through. The `Null` check closes it. `runtime-vpc-only-invocation.json` carries both for this reason.

### `InvokeAgentRuntime*` does not cover `InvokeGateway`

The wildcard reaches all six `InvokeAgentRuntime*` actions including both WebSocket variants, but `InvokeGateway` shares no prefix. `agentcore-baseline.json` lists all seven explicitly.

---

## Validating a change

```bash
aws accessanalyzer validate-policy --region us-east-1 \
  --policy-type SERVICE_CONTROL_POLICY \
  --policy-document file://service-control-policies/agentcore-baseline.json
```

Use `RESOURCE_POLICY` for the files under `resource-policies/`. An empty `findings` array means the syntax, action names, and condition-key names are valid. It does **not** mean the policy denies anything — validation is service-aware but not action-aware, so it accepts a real condition key paired with an action that never populates it. Only a sandbox-OU allow/deny test establishes that a Deny fires.
