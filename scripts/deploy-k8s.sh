#!/usr/bin/env bash
# Despliegue sobre EKS: ALB Controller, Cluster Autoscaler, manifiestos, init de BD, HPA e Ingress.
# Variables requeridas (las exporta el workflow desde `terraform output` y los secrets):
#   AWS_REGION CLUSTER_NAME ACCOUNT_ID VPC_ID ALB_SG_ID RDS_ENDPOINT ASG_NAME DB_USER DB_PASSWORD
# Opcional: FORCE_RESTART=true  -> rollout restart (para tomar imagenes :latest nuevas)
set -euo pipefail
cd "$(dirname "$0")/.."

for v in AWS_REGION CLUSTER_NAME ACCOUNT_ID VPC_ID ALB_SG_ID RDS_ENDPOINT ASG_NAME DB_USER DB_PASSWORD; do
  : "${!v:?Falta la variable $v}"
done
export ACCOUNT_ID RDS_ENDPOINT ALB_SG_ID
NS=freshbox
CA_IMAGE_TAG="${CA_IMAGE_TAG:-v1.35.0}"   # debe coincidir con la version menor de Kubernetes

warn() { echo "::warning::$*"; }

echo "### kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl version --client
echo "### Esperando nodos Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=600s
kubectl get nodes -L topology.kubernetes.io/zone

echo "### AWS Load Balancer Controller (usa el rol del nodo = LabRole)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$AWS_REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set enableShield=false --set enableWaf=false --set enableWafv2=false \
  --wait --timeout 6m

echo "### Cluster Autoscaler (Node Group ${ASG_NAME}: 2-4 nodos)"
cat > /tmp/ca-values.yaml <<CAEOF
cloudProvider: aws
awsRegion: ${AWS_REGION}
image:
  tag: ${CA_IMAGE_TAG}
rbac:
  serviceAccount:
    create: true
    name: cluster-autoscaler
autoscalingGroups:
  - name: ${ASG_NAME}
    minSize: 2
    maxSize: 4
extraArgs:
  balance-similar-node-groups: true
  skip-nodes-with-system-pods: false
CAEOF
helm repo add autoscaler https://kubernetes.github.io/autoscaler >/dev/null
helm repo update >/dev/null
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  -n kube-system -f /tmp/ca-values.yaml --wait --timeout 5m \
  || warn "Cluster Autoscaler no pudo instalarse (revisar permisos de LabRole). Se continua."

echo "### Namespace, ConfigMap y Secret"
kubectl apply -f k8s/namespace.yaml
envsubst '${RDS_ENDPOINT}' < k8s/configmap.yaml | kubectl apply -f -
kubectl -n "$NS" create secret generic freshbox-secret \
  --from-literal=DB_USER="$DB_USER" --from-literal=DB_PASS="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" label secret freshbox-secret project=freshbox-chacon --overwrite

echo "### Migracion de datos: init.sql -> RDS (Job dentro de la VPC)"
kubectl -n "$NS" create configmap db-init-sql --from-file=init.sql=app/init.sql \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$NS" delete job db-init --ignore-not-found
kubectl apply -f k8s/db-init-job.yaml
kubectl -n "$NS" wait --for=condition=complete job/db-init --timeout=900s \
  || { kubectl -n "$NS" logs job/db-init --tail=50 || true; echo "Job db-init fallo"; exit 1; }
kubectl -n "$NS" logs job/db-init --tail=30

echo "### Deployments + Services (5 x 2 replicas)"
for f in k8s/*-deployment.yaml; do
  envsubst '${ACCOUNT_ID}' < "$f" | kubectl apply -f -
done
if [ "${FORCE_RESTART:-false}" = "true" ]; then
  kubectl -n "$NS" rollout restart deployment
fi
for d in frontend get-products create-product update-product delete-product; do
  kubectl -n "$NS" rollout status deployment/"$d" --timeout=600s
done

echo "### HPA"
kubectl apply -f k8s/hpa.yaml

echo "### ALB Ingress"
envsubst '${ALB_SG_ID}' < k8s/ingress.yaml | kubectl apply -f -
for i in $(seq 1 40); do
  ADDR=$(kubectl -n "$NS" get ingress freshbox-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$ADDR" ] && break
  echo "  esperando ADDRESS del Ingress ($i/40)"; sleep 10
done
[ -n "${ADDR:-}" ] || { kubectl -n "$NS" describe ingress freshbox-ingress; echo "El Ingress no obtuvo ADDRESS"; exit 1; }

echo
kubectl -n "$NS" get pods -o wide
kubectl -n "$NS" get svc,hpa,ingress
echo "=================================================="
echo " APP:  http://${ADDR}"
echo "=================================================="
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  { echo "### FreshBox desplegado"; echo "URL: http://${ADDR}"; } >> "$GITHUB_STEP_SUMMARY"
fi
