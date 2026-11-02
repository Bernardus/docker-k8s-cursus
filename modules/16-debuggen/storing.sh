#!/usr/bin/env bash
# Zet een storing klaar in snip-test. Niet spieken: zoek het uit met kubectl.
# Gebruik: ./storing.sh 1|2|3|4|5|eind

set -e
repo="$(cd "$(dirname "$0")/../.." && pwd)"
context=${CONTEXT:-kind-snip}
k() { kubectl --context "$context" -n snip-test "$@"; }

# "Een collega rolt een andere versie uit": de overlay test, met één patch erbij.
uitrollen() {
  tmp="$repo/modules/16-debuggen/.storing"      # Kustomize wil een relatief pad
  mkdir -p "$tmp"
  cat > "$tmp/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../../k8s/overlays/test
patches:
  - patch: |-
$(sed 's/^/      /')
YAML
  trap 'rm -rf "$tmp"' EXIT
  kubectl --context "$context" apply -k "$tmp" >/dev/null
}

# De quota precies vol: er past geen pod meer bij.
quota_krap() {
  n=$(k get pods -o go-template='{{range .items}}{{if not .metadata.deletionTimestamp}}x{{end}}{{end}}' | wc -c | tr -d ' ')
  k patch resourcequota snip-test --type=merge -p "{\"spec\":{\"hard\":{\"pods\":\"$n\"}}}" >/dev/null
}

case "$1" in
  1) uitrollen <<'P'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-web
spec:
  template:
    spec:
      nodeSelector:
        disktype: ssd
P
  ;;
  2) uitrollen <<'P'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-api
spec:
  template:
    spec:
      containers:
        - name: api
          command: ["node", "dist/server.js"]
P
  ;;
  3) uitrollen <<'P'
apiVersion: v1
kind: Service
metadata:
  name: snip-api
spec:
  ports:
    - port: 80
      targetPort: 3001
P
  ;;
  4) quota_krap
     k rollout restart deploy/snip-api >/dev/null
  ;;
  5) uitrollen <<'P'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-api
spec:
  template:
    spec:
      containers:
        - name: api
          env:
            - name: DATABASE_URL
              value: postgres://postgres:$(DB_PASSWORD)@snip-database:5432/snip
P
  ;;
  eind)
     quota_krap
     cat <<'NP' | k apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: snip-api-debug
spec:
  podSelector:
    matchLabels:
      app: snip-api
  policyTypes: [Egress]
  egress:
    - ports:
        - port: 53
          protocol: UDP
NP
     uitrollen <<'P'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: snip-web
spec:
  template:
    spec:
      volumes:
        - name: site
          configMap:
            name: snip-web-site-oud
P
     k rollout restart deploy/snip-api >/dev/null
  ;;
  *) echo "Gebruik: $0 1|2|3|4|5|eind"; exit 1 ;;
esac

echo "Storing $1 staat klaar in snip-test. Succes!"
