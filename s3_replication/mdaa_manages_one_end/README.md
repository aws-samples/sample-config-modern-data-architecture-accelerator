# Cross-Account S3 Replication (MDAA Manages One End)

This sample illustrates cross-account S3 replication for the two topologies where MDAA manages
exactly one end of the replication pair. The other end belongs to another account, and is created
and granted by whoever owns it.

One domain per topology, independent of each other:

| Domain     | MDAA manages         | MDAA creates                                                        | You create in the other account                                             |
| ---------- | -------------------- | ------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `outbound` | the source bucket    | replication rules, replication role, source-key decrypt grant       | destination bucket, its bucket policy, its replica CMK and key policy       |
| `inbound`  | the destination bucket | bucket-policy grant and data lake CMK grant for the external role | sending bucket, its CMK, its replication role and replication rules         |

This architecture may be suitable when:

- You replicate a data lake zone into a DR or archive account you do not manage with MDAA.
- You publish curated data to a consumer account.
- You receive data from a producer account whose buckets are outside MDAA.

For the topology where MDAA manages **both** ends of the pair, see
[../mdaa_manages_both_ends](../mdaa_manages_both_ends/). For the full option reference, see the
[MDAA S3 Data Lake module documentation](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/datalake/datalake-app/README.md#cross-account-replication).

---

## Prerequisites

In addition to the [repository prerequisites](../../README.md#getting-started):

- **Two AWS accounts.** MDAA deploys into one; the far end of each pair lives in the other. Both
  domains can be deployed into the same MDAA account.
- **The far end of each pair must already exist**, before you deploy:

  | Domain     | Must exist beforehand                                                                                                                                   |
  | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `outbound` | The destination bucket, **with versioning enabled**, and a customer managed KMS key in the destination account and region to encrypt the replicas.        |
  | `inbound`  | The sending account's replication role, assumable by `s3.amazonaws.com`. MDAA names it in a bucket policy and a key policy, and both reject a principal that does not resolve. |

- Replication is **not retroactive**. S3 skips objects that predate a rule, so write test objects
  after deployment, not before.

The `inbound` sending bucket must be in the same region as the MDAA deployment: MDAA's inbound key
grant is conditioned on `kms:ViaService = s3.<deployment region>.amazonaws.com`. The `outbound`
destination may be in any region.

---

## Deployment Instructions

1. Edit [mdaa.yaml](mdaa.yaml) to specify an organization name. This must be a globally unique
   name, as it is used in the naming of all deployed resources, some of which are globally named
   (such as S3 buckets).

2. Edit the `context:` values in [mdaa.yaml](mdaa.yaml) to point at the far end of each pair. Every
   value is marked `TODO` and must be replaced. Delete the `repl_dest_*` values and the `outbound`
   domain, or the `repl_source_role_*` values and the `inbound` domain, if you only want one
   topology.

3. Ensure you are authenticated to your target AWS account and have CDK bootstrapped in your target
   region.

4. Deploy:

   ```bash
   npx @aws-mdaa/cli deploy
   ```

5. Complete the grants in the other account. See [After deployment](#after-deployment) — until this
   is done, `outbound` objects replicate with `ReplicationStatus: FAILED` and `inbound` replicates
   nothing at all.

---

## After deployment

Each end needs an identifier the other cannot know in advance, which is why this step comes after
the deploy rather than before it. The constraint is S3's and IAM's, not MDAA's:

- **`outbound`** — the destination's bucket policy and key policy must name MDAA's replication role.
  S3 and KMS both reject a resource policy naming a principal that does not resolve, so the grant
  cannot precede the role.
- **`inbound`** — the sending bucket's role policy and replication configuration must name the MDAA
  destination bucket and its CMK. `PutBucketReplication` is rejected unless the destination exists
  and is versioned, and the key ARN contains a key id AWS generates at creation.

MDAA publishes everything the other account needs to SSM Parameter Store. Read it from there rather
than composing names — MDAA hash-truncates resource names once the composed name reaches its length
limit, but never truncates parameter paths.

```bash
ORG=<your organization name>

# outbound: the replication role the destination account must grant
aws ssm get-parameter --name "/${ORG}/outbound/datalake/role/raw-replication/arn" \
  --query Parameter.Value --output text

# inbound: the destination bucket and CMK the sending account must target
aws ssm get-parameter --name "/${ORG}/inbound/datalake/bucket/curated/name" \
  --query Parameter.Value --output text
aws ssm get-parameter --name "/${ORG}/inbound/datalake/kms/arn" \
  --query Parameter.Value --output text
```

### `outbound` — grants the destination account must add

On the **destination bucket policy**, with MDAA's replication role as the principal:

| Actions                                                        | Resource            |
| -------------------------------------------------------------- | ------------------- |
| `s3:ReplicateObject`, `s3:ReplicateDelete`, `s3:ReplicateTags`  | `<bucket ARN>/*`    |
| `s3:GetBucketVersioning`, `s3:PutBucketVersioning`, `s3:ListBucket` | `<bucket ARN>`  |

On the **replica CMK key policy**, with the same principal:

`kms:Encrypt`, `kms:Decrypt`, `kms:ReEncryptFrom`, `kms:ReEncryptTo`, `kms:GenerateDataKey`,
`kms:GenerateDataKeyWithoutPlaintext`, `kms:DescribeKey` — condition these on
`kms:ViaService = s3.<destination region>.amazonaws.com`.

`kms:Decrypt` accompanies encrypt because MDAA source buckets enable S3 Bucket Keys, whose integrity
check calls `kms:Decrypt` on the replica key.

The bucket-level versioning reads that S3 requires of a replication destination cannot be scoped to
a prefix, so that statement is necessarily whole-bucket. Prefix scoping is enforced by MDAA's rule
filter on the sending side.

### `inbound` — configuration the sending account must add

On its **replication role**:

- `s3:GetReplicationConfiguration`, `s3:ListBucket` on its own bucket ARN
- `s3:GetObjectVersionForReplication`, `s3:GetObjectVersionAcl`, `s3:GetObjectVersionTagging` on its
  own objects
- `s3:ReplicateObject`, `s3:ReplicateDelete`, `s3:ReplicateTags` on `<MDAA bucket ARN>/*`
- `kms:Decrypt`, `kms:DescribeKey` on its own CMK
- `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey`, `kms:GenerateDataKeyWithoutPlaintext`,
  `kms:DescribeKey` on the MDAA data lake CMK

On its **bucket**, a replication configuration naming that role, the MDAA bucket as destination, and
the MDAA data lake CMK as `ReplicaKmsKeyID`. `SourceSelectionCriteria.SseKmsEncryptedObjects` must be
`Enabled` or S3 silently skips every SSE-KMS object.

Use the **full key ARN**, never an alias ARN — an alias resolves in the requester's account, which
cross-account would silently encrypt with the wrong key.

---

## Verify

Each domain has a `data` prefix inside the replication scope and an `other` prefix outside it. The
`other` prefix is what distinguishes correct prefix scoping from a whole-bucket rule.

Assume the domain's `data-admin` role — it is the only role with write access to an MDAA data lake
bucket — then write one object under each prefix:

```bash
SRC=$(aws ssm get-parameter --name "/${ORG}/outbound/datalake/bucket/raw/name" \
  --query Parameter.Value --output text)

echo replicated     | aws s3 cp - "s3://${SRC}/data/probe.txt"
echo not-replicated | aws s3 cp - "s3://${SRC}/other/probe.txt"
```

Replication is asynchronous, so poll rather than checking once. `ReplicationStatus` on the source
object is the single most useful signal — S3 reports `FAILED` there when a destination bucket policy
or KMS grant is wrong, which is the most likely cause given those are the parts MDAA does not manage:

```bash
aws s3api head-object --bucket "${SRC}" --key data/probe.txt \
  --query 'ReplicationStatus' --output text   # want COMPLETED

aws s3api head-object --bucket "${SRC}" --key other/probe.txt \
  --query 'ReplicationStatus' --output text   # want no status at all - no rule matches
```

Then, in the destination account, confirm the in-scope object arrived, that `other/probe.txt` did
not, and that the replica is encrypted with the destination-side key rather than the source's
(`head-object --query SSEKMSKeyId`).

---

## Configurations

### Config Directory Structure

```bash
mdaa_manages_one_end
│   mdaa.yaml
│   tags.yaml
│
└───outbound
│    └───roles.yaml
│    └───datalake.yaml
│
└───inbound
     └───roles.yaml
     └───datalake.yaml
```

### mdaa.yaml

This [configuration](mdaa.yaml) specifies the global, domain, env, and module configurations
required to deploy this sample. Populate the organization name and every `context:` value before
deploying.

### tags.yaml

This [configuration](tags.yaml) specifies the tags to be applied to all deployed resources.

### outbound/roles.yaml, inbound/roles.yaml

These [configurations](outbound/roles.yaml) are used by the MDAA Roles module to deploy the
`data-admin` role for each data lake. Each domain needs its own, because
`generated-role-id:data-admin` resolves against the SSM path of the domain it is referenced from.

### outbound/datalake.yaml

This [configuration](outbound/datalake.yaml) is used by the MDAA S3 Data Lake module to deploy the
source bucket, its replication rules, and the replication role S3 assumes to send.

### inbound/datalake.yaml

This [configuration](inbound/datalake.yaml) is used by the MDAA S3 Data Lake module to deploy the
destination bucket, and to grant the external replication role write access to it and use of the
data lake CMK.

---

## Things to know

- **Replicas arriving from outside bypass the bucket's `ForceKMS` guard.** MDAA's `DenyAES` and
  `ForceKMS` statements apply to `s3:PutObject`, while replication writes via `s3:ReplicateObject`.
  For an `inbound` bucket the external sender therefore chooses the replica encryption key.
- **An `inbound` grant names the whole data lake key, but is scoped to the receiving bucket.** A data
  lake uses one CMK across all its buckets, so the grant carries a `kms:EncryptionContext:aws:s3:arn`
  condition naming that bucket and its granted prefixes, alongside `kms:ViaService` for S3 in the
  deployment region. The external sender can still only write to what its bucket-policy grant names.
- **Deletes are not replicated here.** `outbound.deleteMarkerReplication` is left at its default of
  false, so deleting an object in the source bucket leaves the replica in place and the destination
  stays usable as a recovery point. Set it to true when the destination has to mirror the source
  instead; MDAA then grants the replication role `s3:ReplicateDelete` as well, which the destination
  account's bucket policy must allow for the marker to land. For `inbound`, the decision is the
  sending account's — MDAA always grants `s3:ReplicateDelete` on a bucket receiving replicas, so a
  sender that enables delete markers needs nothing added here.
- **Both sides must allow, cross-account.** A cross-account replication write needs an Allow on the
  sender's identity policy *and* the destination's resource policy. Run both ends in one account and
  the sender's own policy alone is enough, so MDAA's prefix-scoped grant stops being decisive.

---

## Cleanup

`npx @aws-mdaa/cli destroy` removes the MDAA side. Data lake buckets and CMKs are retained by
design, so empty and delete the buckets and schedule the keys for deletion afterwards. The buckets
are versioned, so remove object versions and delete markers, not just objects.

The far end of each pair is yours to clean up in the other account.
