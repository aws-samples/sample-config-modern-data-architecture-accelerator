# Applying the AgentCore prerequisites with LZA

Landing Zone Accelerator specifics for the controls in [YOUR-RESPONSIBILITIES.md](../security-best-practices/YOUR-RESPONSIBILITIES.md). **LZA is not required** — it is one of three ways to apply those controls, and the policy JSON in [`../security-best-practices/policies/`](../security-best-practices/policies/) transfers unchanged to a scripted or console approach.

Written against **LZA v1.16.0**. The config schema changes between releases, so state the version wherever you copy from here. Build from [LZA Universal Configuration](https://github.com/aws/lza-universal-configuration) rather than `reference/sample-configurations/` in the LZA repo, which is now only a pointer.

---

## Service control policies — `organization-config.yaml`

LZA does not accept inline policy JSON. Each policy is a file referenced by path from a `serviceControlPolicies` entry, taking `name`, `description`, `policy`, `type`, `strategy`, and `deploymentTargets`. The files in [`../security-best-practices/policies/service-control-policies/`](../security-best-practices/policies/service-control-policies/) drop in unchanged.

Attach them by the groups in [section 2](../security-best-practices/YOUR-RESPONSIBILITIES.md#2-scp-guardrails) rather than all at once, and test each Deny in a sandbox OU first — a policy with a condition key the service does not populate validates cleanly and enforces nothing.

---

## VPC and endpoints — `network-config.yaml`

For a VPC owned by a central networking team, a `vpcs` entry provides the subnets and the `bedrock-agentcore` interface endpoint, plus supporting ECR API/DKR, STS, CloudWatch Logs, and an S3 gateway endpoint.

- **`bedrock-agentcore` resolves with no override needed.** LZA derives the hosted zone as `<service>.<region>.amazonaws.com` via `HostedZone.getHostedZoneNameForService`; `bedrock-agentcore` contains no dot and is absent from that function's special-case switch and its `ignoreServiceEndpoint` list, so it takes the default — which matches the `PrivateDnsName` AWS returns exactly. No `serviceName` or `hostedZoneName` required. `bedrock-agentcore-control` behaves the same way.
- ⚠️ **A Gateway endpoint under `central: true` will not resolve.** `bedrock-agentcore.gateway` has the wildcard private DNS name `*.gateway.bedrock-agentcore.<region>.amazonaws.com` but is absent from the `wildcardServices` list in `network-vpc-dns-stack.ts`, which decides whether a `*.<zone>` record set is created. LZA derives the zone name correctly and then creates an **apex** record where a wildcard is required, so resolution fails for every gateway hostname. Add the wildcard record out of band, or leave `central` unset and use AWS-native Private DNS.
- ⚠️ **Endpoint ownership collides with MDAA.** Only one endpoint per service per VPC may have Private DNS, so an LZA-created `bedrock-agentcore` endpoint conflicts with one created by MDAA's `networkConfiguration.vpcEndpoint`. Pick an owner: if LZA creates it, omit the `vpcEndpoint` block from the MDAA module config entirely. This is the most likely real-world collision between the two.

Then wire the MDAA module to the LZA-created resources by ID — `vpc_id`, `subnet_id_*`, `security_group_id` in the `context:` block of [`../mdaa.yaml`](../mdaa.yaml).

---

## CloudTrail data events — not expressible in LZA

There is no `global-config.yaml` equivalent. `ICloudTrailSettingsConfig` in v1.16.0 exposes data events as two hard-coded booleans (`s3DataEvents`, `lambdaDataEvents`) with no resource-type or advanced-selector field, so AgentCore data events cannot be configured through LZA at all.

Use the MDAA `audit-trail` module's `dataEventSelectors` instead — see [section 3](../security-best-practices/YOUR-RESPONSIBILITIES.md#3-cloudtrail-data-events). If the trail must be LZA-owned for other reasons, set the selector on it out of band, or wrap that call in a `customizations-config.yaml` stack — a custom resource you own, not an LZA feature.

---

## A complete configuration set

The fragments above are the AgentCore-specific parts. Standing up LZA itself needs a complete set — six mandatory files (`accounts-config.yaml`, `global-config.yaml`, `iam-config.yaml`, `network-config.yaml`, `organization-config.yaml`, `security-config.yaml`) plus optional `customizations-` and `replacements-config.yaml`. That is a landing-zone bootstrap, a different kind of artifact from these fragments.

Deployable example configurations live in this directory.
