# Cross-Account S3 Replication (MDAA Manages Both Ends)

This sample illustrates cross-account S3 replication where MDAA owns the source bucket **and** the
destination bucket, in two different accounts, from one `mdaa.yaml`, in a single `mdaa deploy`.
Nothing is created out of band and there is no post-deploy step.

| Domain      | Account     | MDAA deploys                                                                                          |
| ----------- | ----------- | ----------------------------------------------------------------------------------------------------- |
| `repl-role` | source      | the replication role S3 assumes to send, its ARN parameter RAM-shared with the destination             |
| `receiver`  | destination | data lake, inbound bucket-policy and CMK grants, bucket/CMK ARN parameters RAM-shared with the source  |
| `sender`    | source      | data lake, replication rules referencing the receiver                                                  |

This architecture may be suitable when:

- Both accounts are yours, in one AWS Organization, and both data lakes are MDAA-managed.
- You want the whole pair described in one config and deployed in one run.

Every value that crosses the account boundary does so through a RAM-shared SSM parameter — the same
mechanism the Glue Catalog and SageMaker Unified Studio modules use. Nothing in either direction is
a hand-written resource ARN.

For the topologies where MDAA manages only one end of the pair, see [../mdaa_manages_one_end](../mdaa_manages_one_end/).
For the full option reference, see the
[MDAA S3 Data Lake module documentation](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/datalake/datalake-app/README.md#cross-account-replication).

---

## Prerequisites

In addition to the [repository prerequisites](../../README.md#getting-started):

- **Two AWS accounts, both MDAA accounts.** Both need a CDK bootstrap, and the destination must be
  bootstrapped with `--trust <source account>` — one `mdaa deploy`, run with the source account's
  credentials, deploys the receiver domain into the destination account.

- **Both accounts in the same AWS Organization, with RAM sharing enabled for it.** This is what makes
  the run single-pass. Each side RAM-shares SSM parameters with the other mid-deploy; inside one
  organization with sharing enabled those shares are accepted automatically. Outside it, RAM raises
  an invitation the recipient has to accept, CloudFormation does not wait for it, and the next domain
  fails resolving a parameter it cannot yet read — turning one `mdaa deploy` into three runs with two
  manual acceptances.

  From the organization's **management account**:

  ```bash
  # FeatureSet must be ALL - a consolidated-billing-only organization cannot enable resource sharing
  aws organizations describe-organization --query 'Organization.FeatureSet' --output text

  # Idempotent
  aws ram enable-sharing-with-aws-organization
  ```

  Note what this setting does and does not do. `enable-sharing-with-aws-organization` lets shares to
  principals **inside your own organization** skip the invitation. It grants nothing about receiving
  shares from outside, and there is no recipient-side auto-accept. Two accounts in two different
  organizations, each with the setting enabled, is **not** equivalent: both crossings here would be
  external, so both would raise invitations. The requirement is membership of one organization, not
  merely that each account has one.

- **Same region for both ends.** The sender resolves the receiver's ARNs from RAM-shared SSM
  parameters, and a parameter is resolved in the region of the stack reading it. For cross-region
  replication, use [../mdaa_manages_one_end](../mdaa_manages_one_end/).

Replication is **not retroactive** — S3 skips objects that predate a rule, so write test objects
after deployment, not before.

---

## Deployment Instructions

1. Edit [mdaa.yaml](mdaa.yaml) to specify an organization name. This must be a globally unique name,
   as it is used in the naming of all deployed resources, some of which are globally named (such as
   S3 buckets).

2. Edit the `context:` values in [mdaa.yaml](mdaa.yaml) to your two account IDs. Both are marked
   `TODO` and must be replaced.

3. Ensure the source account is CDK bootstrapped, and the destination account is bootstrapped
   trusting the source:

   ```bash
   # In the destination account
   npx cdk bootstrap aws://<dest_account>/<region> --trust <source_account> \
     --cloudformation-execution-policies arn:aws:iam::aws:policy/AdministratorAccess
   ```

4. Authenticate to the **source** account, and deploy. One pass, both accounts, three domains, in
   order:

   ```bash
   npx @aws-mdaa/cli deploy
   ```

That is the whole deployment. There is no step 5.

---

## Why the domain order is load-bearing

MDAA deploys domains in declaration order and resolves no dependencies between them. Each side of a
replication pair needs something from the other, and the cycle only breaks if the role is deployed
separately, first:

- The receiver's bucket policy and KMS key policy name the replication role as a principal. S3 and
  KMS both reject a policy naming a principal that does not resolve, so the role must precede the
  receiver.
- `PutBucketReplication` on the sender is rejected unless the destination bucket already exists with
  versioning enabled, so the receiver must precede the sender.

Leave the role inside the sender's stack and the two requirements are circular. Deploying it
separately, first, is what makes a single pass possible. The same ordering runs backwards on the way
out, which `mdaa destroy` already does — it reverses domains.

Within a domain, module order comes from `deployStage` in each module's `package.json`:
`@aws-mdaa/roles` is stage 1, `@aws-mdaa/datalake` is stage 2.

Three module features carry this topology, all opt-in and default-off:

1. **`outbound.replicationRole`** (`@aws-mdaa/datalake`) — reference an existing role instead of
   letting the module create one. This is what breaks the deadlock.
2. **`shareParametersWithAccounts`** (`@aws-mdaa/datalake`, module level) — RAM-share the key and
   bucket parameters so the sender can resolve the CMK ARN, whose key id AWS generates at creation.
3. **`shareParametersWithAccounts`** (`@aws-mdaa/roles`, per role) — the same for the replication
   role's ARN, so the receiver can name it without reproducing MDAA's role naming.

Both share fields are explicit lists rather than anything MDAA infers: a RAM share always names its
principals, and neither module can work out who its consumers are.

---

## Verify

Two prefixes on the sender, either side of the replication scope:

| Prefix  | In sender rules | In receiver grant | Expected                      |
| ------- | --------------- | ----------------- | ----------------------------- |
| `data`  | yes             | yes               | `COMPLETED`, object arrives   |
| `other` | no              | n/a               | no `ReplicationStatus` at all |

`other` is what distinguishes correct prefix scoping from a whole-bucket rule that happens to pass.

Keep the two prefix lists in step. The receiver's `inbound.prefixFilters` must cover every prefix the
sender's `outbound.prefixFilters` replicates — a prefix the sender sends but the receiver does not
accept is replicated and then refused, leaving those objects at `ReplicationStatus: FAILED`
indefinitely. S3 does not retry a standing authorization denial, and widening the grant later does
not replicate objects already marked `FAILED`; that needs
[S3 Batch Replication](https://docs.aws.amazon.com/AmazonS3/latest/userguide/s3-batch-replication-batch.html).

Read bucket names from SSM rather than composing them: MDAA hash-truncates resource names once the
composed name reaches its limit, and at this config's org length the bucket names do.

```bash
ORG=<your organization name>

SRC=$(aws ssm get-parameters-by-path --path "/${ORG}/sender/" --recursive \
  --query "Parameters[?ends_with(Name,'/bucket/raw/name')].Value" --output text)
RECV=$(aws --profile <dest-account-profile> ssm get-parameters-by-path --path "/${ORG}/receiver/" \
  --recursive --query "Parameters[?ends_with(Name,'/bucket/curated/name')].Value" --output text)
```

Assume the sender's `data-admin` role — the only role with write access to its data lake — then
write one object under each prefix:

```bash
echo replicated | aws s3 cp - "s3://${SRC}/data/probe.txt"
echo skipped    | aws s3 cp - "s3://${SRC}/other/probe.txt"
```

Replication is asynchronous, so poll. On the source objects:

```bash
for K in data other; do
  printf '%s: ' "$K"
  aws s3api head-object --bucket "${SRC}" --key "${K}/probe.txt" \
    --query 'ReplicationStatus' --output text
done
# want: data COMPLETED / other None
```

Then in the destination account, assuming the receiver's `data-admin` role, confirm that
`data/probe.txt` arrived, that `other/probe.txt` did not, that the replica is encrypted with the
receiver's own CMK (`head-object --query SSEKMSKeyId`), and that it is owned by the destination
bucket owner (`list-objects-v2 --fetch-owner --query 'Contents[].Owner.ID'`).

### Deletes

This sender sets `outbound.deleteMarkerReplication: true`, so a delete is mirrored as well. Delete
the object you just replicated — no `--version-id`, which is what writes a delete marker:

```bash
aws s3api delete-object --bucket "${SRC}" --key data/probe.txt   # want DeleteMarker: true
```

A delete marker carries no `ReplicationStatus` you can read, so the destination is the only place to
look. Poll there, again as the receiver's `data-admin`, until the marker turns up as the object's
latest version:

```bash
aws --profile <dest-account-profile> s3api list-object-versions \
  --bucket "${RECV}" --prefix data/probe.txt \
  --query '{markers: DeleteMarkers[?IsLatest], versions: Versions[].VersionId}'
```

One delete marker, `IsLatest: true`, with the replica version still listed underneath: the deletion
is mirrored, not applied — `data/probe.txt` reads as gone, and the replicated bytes are still there
under their own version id. Leave `deleteMarkerReplication` at its default and the marker never
arrives, which is the behaviour to want when the destination is a recovery point rather than a
mirror.

---

## Configurations

### Config Directory Structure

```bash
mdaa_manages_both_ends
│   mdaa.yaml
│   tags.yaml
│
└───replication_role
│    └───roles.yaml
│
└───receiver
│    └───roles.yaml
│    └───datalake.yaml
│
└───sender
     └───roles.yaml
     └───datalake.yaml
```

### mdaa.yaml

This [configuration](mdaa.yaml) specifies the global, domain, env, and module configurations
required to deploy this sample. Populate the organization name and both `context:` account IDs
before deploying. **Do not reorder the domains** — see
[Why the domain order is load-bearing](#why-the-domain-order-is-load-bearing).

### tags.yaml

This [configuration](tags.yaml) specifies the tags to be applied to all deployed resources.

### replication_role/roles.yaml

This [configuration](replication_role/roles.yaml) is used by the MDAA Roles module to deploy the
replication role in the source account, and to RAM-share its ARN parameter with the destination
account.

### receiver/roles.yaml, sender/roles.yaml

These [configurations](receiver/roles.yaml) are used by the MDAA Roles module to deploy the
`data-admin` role for each data lake. Each domain needs its own, because
`generated-role-id:data-admin` resolves against the SSM path of the domain it is referenced from.

### receiver/datalake.yaml

This [configuration](receiver/datalake.yaml) is used by the MDAA S3 Data Lake module to deploy the
destination data lake, grant the sender's replication role write access to it and use of its CMK,
and RAM-share its bucket and key parameters with the source account.

### sender/datalake.yaml

This [configuration](sender/datalake.yaml) is used by the MDAA S3 Data Lake module to deploy the
source data lake and its replication rules, resolving every far-end identifier from the receiver's
RAM-shared parameters. It is also where `deleteMarkerReplication` turns delete mirroring on.

---

## Things to know

- **Nothing waits for a RAM share's association to propagate** before the next domain reads the
  parameter. CloudFormation considers the share complete on creation, and the association it grants
  is eventually consistent. In practice it has been fast enough; it is not ordered by construction.
- **Replicas arriving via replication bypass the bucket's `ForceKMS` guard.** MDAA's `DenyAES` and
  `ForceKMS` statements apply to `s3:PutObject`, while replication writes via `s3:ReplicateObject`.
- **An `inbound` grant names the whole data lake key, but is scoped to the receiving bucket.** A data
  lake uses one CMK across all its buckets, so the grant carries a `kms:EncryptionContext:aws:s3:arn`
  condition naming that bucket and its granted prefixes, alongside `kms:ViaService` for S3 in the
  deployment region. The sender can still only write to what its bucket-policy grant names.
- **Delete markers are replicated here because the sender asks for them.**
  `outbound.deleteMarkerReplication` is false by default; this sample sets it to true so the two
  lakes mirror, and MDAA grants the replication role `s3:ReplicateDelete` to match. The receiver is
  granted that action either way — the rule that decides belongs to the sending account. Deleting a
  specific object version is never replicated, and neither are delete markers written by a lifecycle
  expiration rule, so a lake whose `lifecycleConfiguration` expires objects cannot be mirrored
  exactly.
- **Both sides must allow, cross-account.** A cross-account replication write needs an Allow on the
  sender's identity policy *and* the destination's resource policy. Run both ends in one account and
  the sender's own policy alone is enough, so the receiver's prefix grant stops being decisive.

---

## Cleanup

`npx @aws-mdaa/cli destroy` unwinds both accounts in one run, reversing the domain order. Buckets and
CMKs are retained by design, so they survive it and have to be emptied and deleted afterwards — the
buckets in two different accounts:

```bash
aws                                  s3 rm "s3://${SRC}"  --recursive
aws --profile <dest-account-profile> s3 rm "s3://${RECV}" --recursive
```

Both buckets are versioned, so `s3 rm` leaves delete markers behind; remove object versions and
delete markers before deleting the buckets themselves. The retained CMKs need scheduling for deletion
in each account.
