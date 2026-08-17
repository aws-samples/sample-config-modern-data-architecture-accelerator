# AgentCore security

Security guidance for the `agentic_app` sample, split by **who has to act**. That is the only distinction that matters when you are trying to work out what is left to do.

| Read this | If you want to know |
| --- | --- |
| **[YOUR-RESPONSIBILITIES.md](YOUR-RESPONSIBILITIES.md)** | What you must do **out of band** — SCPs, the VPC, CloudTrail, IAM, incident response. Start here: it is the only one with a checklist, because it is the only one with work in it |
| **[CONFIGURABLE-CONTROLS.md](CONFIGURABLE-CONTROLS.md)** | What you get by **setting a property**, and which of the two runtime configs demonstrates it |
| **[BUILT-IN-CONTROLS.md](BUILT-IN-CONTROLS.md)** | What the module applies **unconditionally**, and where the authoritative list lives |

Supporting material:

- **[`policies/`](policies/)** — the SCP and resource-policy JSON, portable unchanged across LZA, scripted, and console application. Its [README](policies/README.md) is for people **editing** the policies; deploying them unmodified needs nothing from it
- **[`lza/`](../lza/)** — applying the controls with Landing Zone Accelerator, which is one option and not a requirement

## Scope

This covers the two AgentCore services MDAA deploys: **Runtime** and **Gateway**. Code Interpreter, Browser, Memory, Policy, Evaluations, and Identity's outbound credential flows are not covered — see [AgentCore services this does not cover](YOUR-RESPONSIBILITIES.md#agentcore-services-this-does-not-cover) for what each one's headline risk is and where support is tracked.

## Finding a control

If you are looking for something and cannot tell which file should have it, the test is: **does anything outside your module config have to change?** If yes it is a responsibility; if no it is a configurable or built-in control.

The controls MDAA owns are documented where they live — in [SCHEMA.md](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/ai/bedrock-agentcore-runtime-app/SCHEMA.md), the module README, and the inline comments of the two runtime configs. The two map files here point into those rather than restating them, so a property's behaviour is always described in one place.
