<p align="center">
  <img src="deco/gohan.gif" alt="gohan" width="150">
</p>


<p align="center">
  <img src="deco/beach.webp" alt="sep3" width="1000">
</p>

# FreshBox SpA — EP2 ARY1102 Arquitectura Cloud

Migración de **EC2 + Docker + MySQL en EC2** a **Amazon EKS (5 Deployments x 2 réplicas) + RDS MySQL Multi-AZ**,
desplegada con **Terraform + GitHub Actions** sobre AWS Academy Learner Lab.

## Arquitectura TO-BE (3 capas, 2 AZ)

| Capa | Componentes |
|------|-------------|
| Pública (10.0.0.0/25, 10.0.0.128/25) | ALB (creado por el Ingress Controller), NAT Gateways |
| Privada App (10.0.1.0/25, 10.0.1.128/25) | EKS + Node Group t4g.small (2–4), 5 Deployments, HPA, ECR (imágenes) |
| Privada Data (10.0.2.0/25, 10.0.2.128/25) | RDS MySQL db.t4g.small Multi-AZ, cifrado, snapshots automáticos |

Flujo: `Internet → ALB (SG-ALB :80/443) → Ingress → frontend/Nginx (SG-EKS :80) → Services ClusterIP :3001-3004 → RDS (SG-RDS :3306)`

Nginx enruta `/api/products` por método HTTP: GET→get-products, POST→create-product, PUT→update-product, DELETE→delete-product.

<p align="center">
  <img src="deco/pos.webp" alt="pos" width="1000">
</p>

## Estructura

```
app/            Código del profesor (frontend Nginx + 4 microservicios Node.js + init.sql)
k8s/            Namespace, ConfigMap, 5 Deployments+Services, HPA, Ingress, Job db-init, load-test
modules/        networking, security, ecr, database, eks, monitoring
environments/dev/   Orquestación Terraform
scripts/        build-and-push.sh (ARM64 -> ECR), deploy-k8s.sh, get-outputs.sh
.github/workflows/  plan, apply (infra+imágenes+K8s), k8s-redeploy, destroy
```


## Secrets de GitHub requeridos

`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` (se renuevan en cada sesión del Lab),
`DB_PASSWORD`, `EMAIL_SNS`, `OWNER_NAME` (usar `chacon`; AWS no permite `&` en tags).

## Tagging (provider `default_tags`)

| Tag | Valor |
|-----|-------|
| Project | freshbox-chacon |
| Environment | dev |
| Owner | secret `OWNER_NAME` |
| CostCenter | ecommerce-chacon |
| ManagedBy | terraform |
| Course | ARY1102-EP2 |
| Student | chacon |

## Orden de ejecución

1. Actions → **Terraform Apply + Deploy EKS** (≈ 35–45 min: ECR → imágenes arm64 → VPC/RDS/EKS → ALB Controller → app).
2. Cambios en manifiestos/imágenes: **Redeploy K8s**.
3. Al terminar la evaluación: **Terraform Destroy** (`yes`).

