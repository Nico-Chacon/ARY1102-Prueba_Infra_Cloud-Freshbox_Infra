#!/usr/bin/env bash
# Build ARM64 (nodos t4g = Graviton) + push de las 5 imagenes a ECR.
# Requiere docker buildx + QEMU (en GitHub Actions: setup-qemu-action + setup-buildx-action)
# y login previo a ECR (aws-actions/amazon-ecr-login).
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
cd "$(dirname "$0")/../app"

build() { # $1=nombre repo (sin prefijo)  $2=carpeta
  echo ">> Build & push freshbox-$1 (linux/arm64)"
  docker buildx build --platform linux/arm64 \
    -t "${REGISTRY}/freshbox-$1:latest" --push "$2"
}

build frontend        ./microservicioEKSFrontend
build get-products    ./microserviciosEKSBackend/get-products
build create-product  ./microserviciosEKSBackend/create-product
build update-product  ./microserviciosEKSBackend/update-product
build delete-product  ./microserviciosEKSBackend/delete-product

echo "=== 5 imagenes publicadas en ${REGISTRY} ==="
