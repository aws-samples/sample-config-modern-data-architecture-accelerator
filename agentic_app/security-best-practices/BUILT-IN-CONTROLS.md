# What you get for free

Security controls the AgentCore Runtime module applies unconditionally. There is no property to set and no way to switch them off — they exist because you used the module.

**The authoritative list is maintained with the code**, in the module's [Security/Compliance Details](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-agentcore-runtime-app/README.md#securitycompliance-details). Read that rather than a copy of it. In outline, it covers CMK encryption of the log groups, PII masking on ingestion, TLS in transit, a least-privilege execution role, VPC-mode deployment, and routing agent spans to the agent's own protected log group instead of the account-shared `aws/spans` group.

This file exists to say where to look, and to record three things that list does not currently mention.

## Three execution-role controls

All three **stop applying if you supply your own role** via `roleArn` — MDAA returns a bare reference and cannot modify a role it did not create. That case is a customer obligation; see the `roleArn` item in [YOUR-RESPONSIBILITIES.md](YOUR-RESPONSIBILITIES.md).

| Control | What MDAA does |
| --- | --- |
| Confused-deputy prevention | The trust policy carries `aws:SourceAccount` plus `ArnLike` on `aws:SourceArn`, both scoped to the deploying account and Region — so another account cannot induce the service to assume this role on its behalf |
| Log-resource-policy scoping | `logs:PutResourcePolicy` is granted only on **this agent's own log groups**, so one agent's role cannot rewrite another's |
| Span destination | `UNIFIED_TRACES_DESTINATION_ENABLED` is set to `'true'`, which is what brings span content — prompts, model I/O, tool arguments and results — inside the same CMK, retention, and masking boundary as the agent's logs |

The span destination has a **container-side prerequisite that MDAA cannot enforce**: `aws-opentelemetry-distro>=0.18.0` must be in the image. Below that version the setting is silently ignored and spans go to the shared group with none of those protections. Nothing errors, so this is only visible by checking the image.

## What "for free" does not mean

Two limits worth being explicit about, since an unconditional control can read as a complete one:

- **PII masking holds only for principals without `logs:Unmask`.** MDAA applies the Data Protection policy; who can read past it is an IAM question you own.
- **A least-privilege execution role is not automatically *less* privileged than its callers.** If the role can reach more than the people invoking the agent can, that is a privilege-escalation path — and any code in the microVM, including code the model generates, can read the role's credentials from the metadata service.

Both are in [YOUR-RESPONSIBILITIES.md](YOUR-RESPONSIBILITIES.md).

## Where the boundary is

- Something MDAA does whether you ask or not → here
- Something you set in a config file → [CONFIGURABLE-CONTROLS.md](CONFIGURABLE-CONTROLS.md)
- Something outside the config, in another account, or owned by another team → [YOUR-RESPONSIBILITIES.md](YOUR-RESPONSIBILITIES.md)
