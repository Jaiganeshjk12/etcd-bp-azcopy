# etcd Blueprint (Kasten K10)

This blueprint backs up etcd data from control-plane nodes using the RedHat provided cluster-backup.sh script and uploads the tar archive to Azure Blob using AzCopy(using workload authentication). It also records the backup artifact path with kando so Kasten can track and use it in delete operations.

## Security notes (short)

- `AZCOPY_AUTO_LOGIN_TYPE=workload` means AzCopy authenticates with the Federated workload identity token.
- Federated identity setup steps are intentionally not duplicated here. Use the Kasten reference: https://docs.kasten.io/latest/install/openshift/helm#federated-identity and the blueprint assumes that the federated identity setup done for Kasten.
- The backup pod runs on control-plane nodes and mounts `/etc/kubernetes` as read-only hostPath to access static pod backup scripts and cert assets.
- `seLinuxOptions.type: spc_t` is required on OpenShift for this workload because the pod must read hostPath-mounted control-plane files under `/etc/kubernetes`. Without `spc_t`, SELinux policy can deny access to these host files even when the mount is present, causing the backup script to fail before snapshot/upload.

## What this blueprint uses

- Single KubeTask pod (custom image) with required tools: `cluster-backup.sh` dependencies, `etcdctl`/`etcdutl`, `azcopy`, and `kando`
- Temporary ephemeral volume mounted at `/backup` to hold backup artifacts during the phase
- Control-plane node scheduling (affinity/tolerations) to access static pod resources from `/etc/kubernetes`
- Azure Blob destination from the K10 profile

## Build and push the image

The image definition is maintained in `Dockerfile` in this repository.

Build amd64 image and push directly (example tag):

```bash
docker buildx build --platform linux/amd64 -t <your-registry>/kanister-etcd-azcopy:3.6.11 --push .
```

Verify:

```bash
docker run --rm --platform linux/amd64 <your-registry>/kanister-etcd-azcopy:3.6.11 "azcopy --version && kando --help >/dev/null && etcdctl version && etcdutl version"
```

Set the blueprint image in `etcd-azcopy.yaml` to your pushed tag before policy execution.

## Create the blueprint in Kasten namespace

Apply the blueprint in the Kasten namespace (for example `kasten-io`):

```bash
kubectl -n kasten-io apply -f etcd-azcopy.yaml
```

## Create and annotate the workload namespace

Create the namespace resource to attach the blueprint:

```bash
kubectl create ns etcd-backup
```

Annotate it to use this blueprint:

```bash
kubectl annotate ns etcd-backup kanister.kasten.io/blueprint=etcd-azcopy
```

## Create a Policy in K10

1. Open Kasten K10 UI.
2. Go to Policies and create a new policy.
3. Select namespace `etcd-backup`.
4. Choose the backup action and set your schedule/retention as per the requirement.
5. Enable export as needed
6. Select the location profile for Kanister action. 
7. Save and run the policy.

K10 will detect the namespace annotation and use the `etcd-azcopy` Kanister blueprint for backup actions.

## Limitations and tradeoffs

- This blueprint uses AzCopy directly for export/delete and does not provide immutability controls by itself.
- The blueprint doesn't provide a restore functionality in itself.
- This blueprint reads control-plane host resources from `/etc/kubernetes` and requires elevated SELinux context (`spc_t`) for that access pattern on OpenShift.
- A harmless warning log about `ETCDCTL_API=3` can appear from node-provided etcd scripts/env on newer etcdctl versions; this is non-blocking when snapshot creation, archive creation, and upload complete successfully.
