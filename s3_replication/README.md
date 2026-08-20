# Cross-Account S3 Replication

Two samples for replicating data lake objects into another AWS account, differing in how much of the
replication pair MDAA manages. Pick by which end you own.

| Sample                                                     | MDAA manages                             | You provide                                                       | Deploy |
| ---------------------------------------------------------- | ---------------------------------------- | ----------------------------------------------------------------- | ------ |
| [mdaa_manages_one_end](mdaa_manages_one_end/)               | the source bucket, or the destination bucket | the other end, in an account MDAA does not deploy into            | one deploy, then grants in the other account |
| [mdaa_manages_both_ends](mdaa_manages_both_ends/)           | both ends, in two accounts               | two accounts in one AWS Organization, both CDK bootstrapped        | one deploy, nothing else |

- **[mdaa_manages_one_end](mdaa_manages_one_end/)** — the common case. The far end belongs to
  somebody else: a partner account, a DR account outside MDAA, a producer whose buckets you do not
  control. It covers both directions, as two independent domains: `outbound` (MDAA owns the source)
  and `inbound` (MDAA owns the destination). Because the far end is not MDAA's, some grants have to
  be applied there after the deploy. It is also the sample to use for **cross-region** replication.

- **[mdaa_manages_both_ends](mdaa_manages_both_ends/)** — both accounts are yours and both data lakes
  are MDAA-managed. Everything on both sides comes from one `mdaa.yaml` in a single `mdaa deploy`,
  with no out-of-band resources and no post-deploy step. Every identifier that crosses the account
  boundary does so through a RAM-shared SSM parameter, which is why both accounts must be in the same
  AWS Organization and the same region.

## Concepts that apply to both

- **Replication rules always live on the source bucket.** So MDAA creates rules only where a bucket
  declares `replication.outbound`. `replication.inbound` creates grants, never rules.

- **A cross-account replication write needs an Allow on both sides** — the sender's identity policy
  *and* the destination's resource policy. This is what makes the destination's prefix grant
  meaningful. Run both ends in one account and the sender's own policy alone suffices, so the
  destination's grant stops being decisive.

- **`destinationKmsKeyArn` is required on `outbound`, and must be a customer managed key.** MDAA
  buckets always encrypt with a CMK, and S3 replicates no SSE-KMS object unless the rule names a
  replica key in the destination region. AWS managed keys cannot be used cross-account. Always use
  the full key ARN — an alias ARN resolves in the requester's account, which cross-account would
  silently encrypt with the wrong key.

- **Replication is not retroactive.** S3 skips objects that predate a rule, so write test objects
  after deploying, not before.

- **`ReplicationStatus` on the source object is the signal to read.** S3 reports `FAILED` there when
  a destination bucket policy or KMS grant is wrong, and reports no status at all when no rule
  matches the object.

- **Replicas bypass the bucket's `ForceKMS` guard.** MDAA's `DenyAES` and `ForceKMS` statements apply
  to `s3:PutObject`, while replication writes via `s3:ReplicateObject`, so the sending side chooses
  the replica encryption key.

- **Deletes are not replicated unless the sending side asks.** `outbound.deleteMarkerReplication`
  defaults to false, so deleting an object leaves the replica in place and the destination stays
  usable as a recovery point after an accidental or malicious delete.
  [mdaa_manages_both_ends](mdaa_manages_both_ends/) sets it to true, because there both lakes are
  yours and meant to mirror; [mdaa_manages_one_end](mdaa_manages_one_end/) keeps the default. Two S3
  limits apply either way: deleting a specific object version is never replicated, and neither are
  delete markers written by a lifecycle expiration rule. A bucket receiving replicas is always
  granted `s3:ReplicateDelete`, since the rule that decides belongs to the sending account and may
  enable delete markers at any time.

- **Both samples include an `other` prefix that deliberately does not replicate**, outside every
  `prefixFilter`, to show that scoping is enforced rather than incidental. It is a correct
  configuration, not a caveat — nothing about it needs removing before production use.

- **When replication is configured on both ends, the inbound prefixes must cover the outbound ones.**
  A prefix the sender replicates but the destination does not accept is replicated and then refused,
  leaving those objects at `ReplicationStatus: FAILED` indefinitely — S3 does not retry a standing
  authorization denial, and widening the grant later does not fix objects already marked `FAILED`.

For the full option reference, see the
[MDAA S3 Data Lake module documentation](https://github.com/aws/modern-data-architecture-accelerator/blob/main/packages/apps/datalake/datalake-app/README.md#cross-account-replication).
