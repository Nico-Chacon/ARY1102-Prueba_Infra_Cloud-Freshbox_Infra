# Guía paso a paso — FreshBox SpA EP2 (EKS + RDS Multi-AZ)

**Cómo usar esta guía**

- Cada **Fase** corresponde a un bloque del informe / defensa. Al inicio de cada una indico dónde se usa la evidencia.
- 📸 **SS-xx** = saca captura de pantalla. Guárdala con el nombre indicado (`SS-07_vpc_cidr.png`, etc.). Así después solo armas el informe pegando en orden.
- 🔒 Nunca captures contraseñas, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` ni el valor del Secret de Kubernetes.
- **Tagging:** todo recurso creado por Terraform ya lleva los tags con `chacon` (ver Fase 0, paso 2). Solo en lo que creas **a mano** (bucket S3) debes ponerlos tú.

| Tag | Valor |
|---|---|
| Project | `freshbox-chacon` |
| Environment | `dev` |
| Owner | `chacon` |
| CostCenter | `ecommerce-chacon` |
| ManagedBy | `terraform` (o `manual` en lo creado a mano) |
| Course | `ARY1102-EP2` |
| Student | `chacon` |

> **Tiempo estimado:** Fase 0–1: 1 h · Fase 3 (el workflow corre solo): 40 min · Resto: 2–3 h. Deja el despliegue funcionando **antes** del día de la defensa.

---

## FASE 0 — Preparación (cuentas, bucket de estado, repo y secrets)

*Sirve para:* base de todo el despliegue. Evidencia mínima.

**Paso 1 — Iniciar el Learner Lab del curso EP2**
1. Entra al curso nuevo de AWS Academy habilitado para EP2 → *Modules* → *Learner Lab*.
2. Click **Start Lab**. Espera a que el círculo junto a "AWS" quede **verde**.
3. Click **AWS Details** → **AWS CLI: Show**. Verás `aws_access_key_id`, `aws_secret_access_key` y `aws_session_token`. Déjalo abierto (los usarás en el Paso 4).
4. Click en **AWS** (círculo verde) para abrir la consola. Región: **us-east-1 (N. Virginia)**. Verifica arriba a la derecha.
5. Comprueba que existe el rol `LabRole`: *IAM → Roles → buscar "LabRole"*. (Terraform lo usa para EKS y los nodos porque Academy no deja crear roles.)

**Paso 2 — Crear el bucket S3 para el estado de Terraform**
1. *S3 → Create bucket*.
2. Nombre: `chacon-freshbox-ep2-tfstate` (si dice que ya existe, usa otro y cámbialo en `environments/dev/backend.tf`).
3. Región us-east-1. **Bucket Versioning: Enable**. Resto por defecto.
4. En **Tags** agrega los 7 tags de la tabla de arriba (con `ManagedBy = manual`).
5. *Create bucket*.

📸 **SS-01 `SS-01_bucket_tfstate_tags.png`** — Bucket creado → pestaña *Properties* mostrando Versioning habilitado y los Tags con `chacon`.

**Paso 3 — Crear el repositorio en GitHub**
1. GitHub → *New repository* → nombre `freshbox-ep2`, **Private**, sin README.
2. En tu PC, descomprime el proyecto entregado y, dentro de la carpeta:
```bash
git init -b main
git add .
git commit -m "FreshBox EP2: EKS + RDS Multi-AZ"
git remote add origin https://github.com/<TU_USUARIO>/freshbox-ep2.git
```
> **No hagas `git push` todavía**: primero van los secrets (Paso 4), porque el push dispara el despliegue.

**Paso 4 — Cargar los secrets**
GitHub → repo → *Settings → Secrets and variables → Actions → New repository secret*. Crea estos 6:

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | del Paso 1 |
| `AWS_SECRET_ACCESS_KEY` | del Paso 1 |
| `AWS_SESSION_TOKEN` | del Paso 1 (**largo**, cópialo completo) |
| `DB_PASSWORD` | una clave tuya, mín. 8 caracteres, sin `@` `/` `"` ni espacios |
| `EMAIL_SNS` | tu correo (recibirás alertas) |
| `OWNER_NAME` | `chacon` (AWS **no acepta `&`** en tags, no uses "Chacon & Corp") |

📸 **SS-02 `SS-02_github_secrets.png`** — Lista de secrets (solo nombres; GitHub no muestra valores).

> ⚠️ **Las 3 credenciales AWS caducan** cada vez que termina la sesión del Lab (~4 h). Cada vez que inicies el Lab de nuevo, vuelve a copiar y actualizar esos 3 secrets antes de ejecutar cualquier workflow.

---

## FASE 1 — Diseño de la arquitectura TO-BE (diagrama)

*Sirve para:* **Presentación 2.1 (IE3.2.1, 20 %)** e informe **1.3**.

**Paso 1 — Tabla de direccionamiento (cópiala al informe)**

| Capa | AZ-a | AZ-b | Contenido |
|---|---|---|---|
| Pública | 10.0.0.0/25 | 10.0.0.128/25 | ALB, NAT Gateway |
| Privada App | 10.0.1.0/25 | 10.0.1.128/25 | Nodos EKS, pods |
| Privada Data | 10.0.2.0/25 | 10.0.2.128/25 | RDS Primary / Standby |

VPC: `10.0.0.0/22`.

**Paso 2 — Dibujar en draw.io (https://app.diagrams.net)**
Usa la librería *AWS Architecture 2025* (menú izquierdo → *More Shapes → AWS*). Dibuja de afuera hacia adentro:

1. Caja **AWS Cloud → Region us-east-1 → VPC 10.0.0.0/22**.
2. Dos columnas verticales: **AZ us-east-1a** y **AZ us-east-1b**.
3. Tres filas horizontales (capas), rotuladas **Capa 1 Pública / Capa 2 Privada App / Capa 3 Privada Data**, con sus 6 subredes y CIDR (tabla anterior).
4. **Capa 1:** Internet Gateway (borde de la VPC), **ALB** (abarcando ambas subredes), 1 **NAT Gateway** por AZ.
5. **Capa 2:** recuadro **Amazon EKS cluster `freshbox-cluster`** y dentro **Node Group (t4g.small, min 2 / max 4)**: un nodo por AZ (mínimo) y los **5 pods** (frontend, get-products, create-product, update-product, delete-product). Agrega **Ingress Controller** (pod en kube-system) y **HPA**.
6. **Capa 3:** **RDS MySQL Primary** (AZ-a) y **RDS Standby** (AZ-b) con flecha de **replicación síncrona**; rotula "Multi-AZ, cifrado, snapshots automáticos".
7. Fuera de la VPC: **Amazon ECR** (5 imágenes), **CloudWatch Container Insights**, **SNS**.
8. **Security Groups** como recuadros punteados de color: `SG-ALB` (capa 1), `SG-EKS-App` (capa 2), `SG-RDS` (capa 3).

**Paso 3 — Flechas rotuladas (esto da el puntaje de "flujos de comunicación")**

| Flecha | Rótulo |
|---|---|
| Usuario → ALB | HTTP 80/443 (0.0.0.0/0) |
| ALB → frontend | 80 (origen SG-ALB) |
| frontend (Nginx) → Services | ClusterIP 3001 / 3002 / 3003 / 3004 |
| pods backend → RDS | MySQL 3306 (origen SG-EKS-App) |
| Nodos → NAT → Internet | salida controlada |
| Nodos → ECR | pull de imágenes |
| Nodos → CloudWatch | métricas/logs |
| Primary → Standby | replicación síncrona |

> Importante: el ALB solo habla con el **frontend:80** (así lo dice la tabla de Security Groups del enunciado). Nginx es quien reparte por método HTTP a los 4 backends dentro del cluster. Dibújalo así para que coincida con lo desplegado.

**Paso 4 — Exportar:** *File → Export as → PNG*, zoom 200 %, "Border width 10". Guarda también el `.drawio`.

📸 **SS-03 `SS-03_diagrama_TOBE.png`** — Diagrama final legible (también va en la diapositiva de arquitectura).

---

## FASE 2 — Comparación de arquitecturas con evidencia de costos

*Sirve para:* **Informe 1.1 (IE3.1.1, 10 %)** y **1.2 (IE3.1.2, 10 %)**.

**Paso 1 — Calculadora de precios**
Entra a https://calculator.aws/ (región **US East (N. Virginia)**) y crea **dos estimaciones**, 730 h/mes:

**Estimación A — Arquitectura tradicional (EP1):** 2 × EC2 `t3.small` + EBS gp3 50 GB c/u, 1 × EC2 `t3.small` para MySQL (o 2 si lo tenías replicado a mano), 1 ALB, 1 NAT Gateway.

**Estimación B — EKS + PaaS (EP2):** 1 × EKS cluster, 3 × EC2 `t4g.small` (EBS gp3 20 GB), RDS MySQL `db.t4g.small` **Multi-AZ** 20 GB gp3, 1 ALB, **2** NAT Gateway, ECR (~1 GB), CloudWatch Container Insights (logs/metrics estimados).

Valores de referencia aproximados (verifica en la calculadora; úsalos solo como control): control plane EKS ≈ US$0,10/h; `t4g.small` ≈ US$0,017/h; NAT ≈ US$0,045/h + tráfico; ALB ≈ US$0,0225/h + LCU; RDS Multi-AZ ≈ el doble de la instancia Single-AZ.

📸 **SS-04 `SS-04_calc_tradicional.png`** — Resumen de la Estimación A (total mensual).
📸 **SS-05 `SS-05_calc_eks_rds.png`** — Resumen de la Estimación B (total mensual).

**Paso 2 — Tabla comparativa (la completas con tus palabras en el informe)**
Crea una tabla con **columnas**: *EC2+Docker (tradicional)* | *EKS (orquestación)* | *RDS / PaaS*, y **filas**: Costo de recursos · Costo de administración (horas/mes) · Operación (despliegues, parches) · Escalabilidad (granularidad) · Rendimiento · Disponibilidad / RTO · Seguridad · Ventajas · Limitaciones.
Ideas que debes argumentar con el caso FreshBox: contenedores manuales vs Deployments auto-reparables · escalado por instancia vs por pod (HPA) y por nodo (Autoscaler) · MySQL en EC2 sin HA (caída = ventas detenidas) vs Multi-AZ con failover automático y snapshots · costo fijo extra del control plane y NAT vs horas de administración ahorradas.

**Paso 3 — Estrategia de modernización (1.2):** redacta en 3 fases (1) contenerizar y publicar en ECR, (2) migrar BD a RDS Multi-AZ, (3) migrar workloads a EKS con HPA/observabilidad. Para cada una: impacto **operacional, técnico y de negocio** y su relación con los objetivos de FreshBox (escalabilidad automática, alta disponibilidad, optimización operacional y financiera).

---

## FASE 3 — Despliegue de la infraestructura (Terraform + GitHub Actions)

*Sirve para:* **Presentación 2.2 (IE3.3.1, 30 %)** e informe **1.3** (seguridad, HA, escalabilidad).

**Paso 1 — Lanzar el pipeline**
1. En tu PC: `git push -u origin main`. Esto dispara automáticamente **Terraform Apply + Deploy EKS** (no hace falta pulsar *Run workflow*; si lo haces, quedará en cola).
2. GitHub → pestaña **Actions** → entra a la ejecución. El orden es: validate → ECR → build/push de 5 imágenes arm64 → plan/apply (VPC, SG, RDS, EKS, nodos, add-ons) → ALB Controller + Autoscaler → manifiestos → init BD → HPA → Ingress.
3. Dura **35–45 min** (RDS Multi-AZ y EKS son lo más lento). Al final, el último paso imprime `APP: http://<dns-del-alb>`.

📸 **SS-06 `SS-06_actions_ok.png`** — Ejecución con todos los pasos en verde y la duración total.

> Si falla un paso, abre el log, copia el error y revisa la **tabla de problemas frecuentes** al final. Tras corregir, usa *Re-run failed jobs* (Terraform es idempotente).

**Paso 2 — Red (Consola → VPC)**
1. *VPC → Your VPCs*: filtra `freshbox`.
📸 **SS-07 `SS-07_vpc_cidr.png`** — VPC `freshbox-vpc` con CIDR `10.0.0.0/22`.
2. *VPC → Subnets*: filtra por la VPC. Deben verse 6 subredes `/25` en 2 AZ. Agrega columnas *Availability Zone* y *IPv4 CIDR*.
📸 **SS-08 `SS-08_subredes.png`** — Las 6 subredes con AZ y CIDR.
3. *VPC →* tu VPC → pestaña **Resource map**.
📸 **SS-09 `SS-09_resource_map.png`** — Mapa de recursos (subredes, route tables, IGW, 2 NAT).
4. *Route tables* → `freshbox-private-data-rt-1`: solo ruta *local*. Compárala con `freshbox-private-app-rt-1` (0.0.0.0/0 → NAT).
📸 **SS-10 `SS-10_rt_data_vs_app.png`** — Rutas de la tabla Data (sin Internet) y de la tabla App (NAT).

**Paso 3 — Security Groups por capa**
*VPC → Security groups* → abre cada uno → pestaña **Inbound rules**:
📸 **SS-11 `SS-11_sg_alb.png`** — `freshbox-alb-sg`: 80 y 443 desde `0.0.0.0/0`.
📸 **SS-12 `SS-12_sg_eks_app.png`** — `freshbox-eks-app-sg`: 80 y 443 con origen = SG del ALB (+ regla interna self).
📸 **SS-13 `SS-13_sg_rds.png`** — `freshbox-rds-sg`: 3306 con origen = SG de EKS App.

**Paso 4 — ECR**
*ECR → Private repositories*.
📸 **SS-14 `SS-14_ecr_repos.png`** — Los 5 repos `freshbox-frontend`, `-get-products`, `-create-product`, `-update-product`, `-delete-product`.
Abre uno (ej. `freshbox-get-products`).
📸 **SS-15 `SS-15_ecr_imagen_latest.png`** — Imagen con tag `latest`, fecha de push, tamaño y escaneo (scan on push).

**Paso 5 — RDS Multi-AZ**
*RDS → Databases → `freshbox-db`*.
📸 **SS-16 `SS-16_rds_resumen.png`** — Estado *Available*, clase `db.t4g.small`, **Multi-AZ: Yes**, engine MySQL.
Pestaña **Configuration**:
📸 **SS-17 `SS-17_rds_config.png`** — *Encryption: Enabled*, almacenamiento gp3, **Backup retention 7 days** (snapshots automáticos), Multi-AZ.
Pestaña **Connectivity & security**:
📸 **SS-18 `SS-18_rds_conectividad.png`** — **Publicly accessible: No**, subnet group (subredes Data), SG `freshbox-rds-sg`, AZ primaria y **Secondary zone**.
Pestaña **Maintenance & backups**:
📸 **SS-19 `SS-19_rds_backups.png`** — Ventana de backup y *Automated backups* / snapshots.

**Paso 6 — EKS y Node Group**
*EKS → Clusters → `freshbox-cluster`*.
📸 **SS-20 `SS-20_eks_cluster.png`** — Status *Active*, versión de Kubernetes, endpoint.
Pestaña **Compute → Node groups → `freshbox-cluster-ng`**:
📸 **SS-21 `SS-21_nodegroup_scaling.png`** — `t4g.small`, AMI ARM, **Min 2 / Desired 3 / Max 4**, subredes (2 AZ).
Pestaña **Compute → Nodes**:
📸 **SS-22 `SS-22_nodos_ready.png`** — 3 nodos *Ready* en AZ distintas.
Pestaña **Add-ons**:
📸 **SS-23 `SS-23_eks_addons.png`** — `metrics-server`, `amazon-cloudwatch-observability`, `vpc-cni`, `coredns`, `kube-proxy` en *Active*.

**Paso 7 — Cifrado EBS de los nodos**
*EC2 → Volumes* (filtra por Tag `Project = freshbox-chacon`).
📸 **SS-24 `SS-24_ebs_cifrado.png`** — Columna **Encryption = Encrypted** en los volúmenes de los nodos.
*EC2 → Instances*:
📸 **SS-25 `SS-25_ec2_nodos_az.png`** — Instancias `t4g.small` en us-east-1a y us-east-1b (columna Availability zone).

**Paso 8 — Verificar el tagging**
*Resource Groups & Tag Editor → Tag Editor* → Regions: us-east-1 → Resource types: *All supported resource types* → Tag: `Project` = `freshbox-chacon` → *Search resources*.
📸 **SS-26 `SS-26_tag_editor.png`** — Lista de recursos con los tags `freshbox-chacon`.

---

## FASE 4 — Aplicación en Kubernetes (CloudShell + kubectl)

*Sirve para:* **Presentación 2.2** (5 pods, manifiestos, imágenes de ECR, Ingress) .

**Paso 1 — Abrir CloudShell y conectar kubectl**
1. Consola AWS → ícono **CloudShell** (barra superior, `>_`). Región us-east-1.
2. Instala kubectl (solo la primera vez; si `kubectl version --client` ya funciona, sáltalo):
```bash
mkdir -p ~/bin && cd ~/bin
ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
curl -sLO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/$ARCH/kubectl"
chmod +x kubectl && export PATH=$HOME/bin:$PATH && cd ~
```
3. Conéctate al cluster:
```bash
aws eks update-kubeconfig --name freshbox-cluster --region us-east-1
kubectl get nodes
```
> Si responde `Unauthorized`: el rol con que entraste a la consola no es el que creó el cluster. Ver tabla de problemas.

**Paso 2 — Nodos y pods**
```bash
kubectl get nodes -L topology.kubernetes.io/zone,node.kubernetes.io/instance-type
```
📸 **SS-27 `SS-27_kubectl_nodes.png`** — 3 nodos Ready, `t4g.small`, 2 zonas distintas.
```bash
kubectl get pods -n freshbox -o wide
```
📸 **SS-28 `SS-28_kubectl_pods.png`** — **10 pods Running** (5 Deployments × 2), repartidos en nodos distintos.
```bash
kubectl get deploy,svc -n freshbox
```
📸 **SS-29 `SS-29_kubectl_deploy_svc.png`** — 5 Deployments `2/2` y 5 Services **ClusterIP** (80, 3001, 3002, 3003, 3004).

**Paso 3 — Imágenes ECR realmente usadas y componentes del sistema**
```bash
kubectl get deploy -n freshbox -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
kubectl get pods -n kube-system
kubectl get pods -n amazon-cloudwatch
```
📸 **SS-30 `SS-30_imagenes_ecr_y_sistema.png`** — Imágenes `…dkr.ecr.us-east-1.amazonaws.com/freshbox-*:latest` y pods del sistema (aws-load-balancer-controller, cluster-autoscaler, metrics-server, coredns; cloudwatch-agent y fluent-bit).

**Paso 4 — ConfigMap y Secret (sin mostrar la clave)**
```bash
kubectl -n freshbox get configmap freshbox-config -o yaml
kubectl -n freshbox describe secret freshbox-secret
```
📸 **SS-31 `SS-31_configmap_secret.png`** — ConfigMap con `DB_HOST` = endpoint RDS y Secret mostrando solo nombres/tamaños (`describe` no revela el valor). **No uses `-o yaml` en el Secret.**

**Paso 5 — Migración de datos a RDS**
```bash
kubectl -n freshbox logs job/db-init
```
📸 **SS-32 `SS-32_job_db_init.png`** — Log del Job: "cargando init.sql", los 5 productos y "Migración de datos OK".

Verificación directa en RDS (desde dentro de la VPC):
```bash
RDS=$(kubectl -n freshbox get configmap freshbox-config -o jsonpath='{.data.DB_HOST}')
kubectl -n freshbox run mysql-check --rm -it --restart=Never --image=mysql:8.4 \
  --env="MYSQL_PWD=$(kubectl -n freshbox get secret freshbox-secret -o jsonpath='{.data.DB_PASS}' | base64 -d)" \
  -- mysql -h "$RDS" -u admin -e "SELECT COUNT(*) AS productos FROM freshbox.productos; SHOW VARIABLES LIKE 'version';"
```
📸 **SS-33 `SS-33_rds_datos_migrados.png`** — `productos = 5` y versión de MySQL.

**Paso 6 — ALB Ingress**
```bash
kubectl -n freshbox get ingress
kubectl -n freshbox describe ingress freshbox-ingress | tail -20
```
📸 **SS-34 `SS-34_ingress_address.png`** — Ingress con **ADDRESS** = DNS del ALB.
Consola → *EC2 → Load Balancers → `freshbox-chacon-alb`*:
📸 **SS-35 `SS-35_alb_detalle.png`** — ALB *internet-facing*, 2 subredes públicas en 2 AZ, SG `freshbox-alb-sg`.
Pestaña **Listeners and rules** y luego *Target groups* → pestaña **Targets**:
📸 **SS-36 `SS-36_alb_targets_healthy.png`** — Targets (IP de pods frontend) en **Healthy**.
Pestaña **Tags** del ALB:
📸 **SS-37 `SS-37_alb_tags.png`** — Tags `Project = freshbox-chacon`, etc. (vienen del Ingress).

---

## FASE 5 — Validación funcional del CRUD (extremo a extremo)

*Sirve para:* **Presentación 2.2 y 2.3 (IE3.3.1 / IE3.3.2)**.

**Paso 1 — Obtener la URL**
```bash
ALB=$(kubectl -n freshbox get ingress freshbox-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo http://$ALB
```
Pégala en el navegador.
📸 **SS-38 `SS-38_app_listado_GET.png`** — Catálogo FreshBox con los 5 productos (GET). Debe verse la URL del ALB en la barra.

**Paso 2 — CRUD desde la interfaz web (usa un producto de prueba)**
1. **POST:** formulario *Nuevo Producto* → Nombre `Producto Chacon Test`, Precio `1000`, Stock `10`, Categoría `Test` → *Guardar*.
📸 **SS-39 `SS-39_crud_POST.png`** — Producto nuevo en la tabla.
2. **PUT:** botón *Editar* en ese producto → cambia precio a `1500` → *Guardar*.
📸 **SS-40 `SS-40_crud_PUT.png`** — Precio actualizado.
3. **DELETE:** botón *Eliminar* → confirmar.
📸 **SS-41 `SS-41_crud_DELETE.png`** — El producto ya no aparece.

**Paso 3 — Mismo CRUD por API (evidencia con códigos HTTP)**
```bash
echo "--- GET";    curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$ALB/api/products
echo "--- POST";   ID=$(curl -s -X POST http://$ALB/api/products -H 'Content-Type: application/json' \
  -d '{"nombre":"Test API Chacon","descripcion":"prueba","precio":2000,"stock":5,"categoria":"Test"}' | tee /dev/stderr | jq -r .id); echo; echo "id=$ID"
echo "--- GET id"; curl -s http://$ALB/api/products/$ID; echo
echo "--- PUT";    curl -s -X PUT http://$ALB/api/products/$ID -H 'Content-Type: application/json' \
  -d '{"nombre":"Test API Chacon","descripcion":"editado","precio":2500,"stock":8,"categoria":"Test"}'; echo
echo "--- DELETE"; curl -s -X DELETE http://$ALB/api/products/$ID; echo
echo "--- GET id (debe dar 404)"; curl -s -o /dev/null -w "HTTP %{http_code}\n" http://$ALB/api/products/$ID
```
📸 **SS-42 `SS-42_crud_curl.png`** — Salida completa: GET 200 → POST (201 con el objeto) → PUT → DELETE → GET 404.

> Explicación para la defensa: Nginx (en el pod frontend) enruta `/api/products` según el método HTTP: GET→`get-products:3001`, POST→`create-product:3002`, PUT→`update-product:3003`, DELETE→`delete-product:3004`; cada microservicio escribe/lee en RDS.

---

## FASE 6 — Monitoreo (CloudWatch Container Insights)

*Sirve para:* **Presentación 2.3 (IE3.3.2, 10 %)**.

**Paso 1 — Confirmar el correo SNS:** revisa tu correo y pulsa **Confirm subscription** en el mensaje de AWS Notifications (si no, no llegarán alertas).

**Paso 2 — Container Insights** (espera ~5–10 min desde que corrió el despliegue)
1. *CloudWatch → Insights → Container Insights → Performance monitoring*. Selector: **EKS Clusters** → `freshbox-cluster`.
📸 **SS-43 `SS-43_ci_cluster.png`** — Vista del cluster: CPU/memoria de nodos y cantidad de nodos/pods.
2. Cambia el selector a **EKS Pods** y filtra Namespace `freshbox`.
📸 **SS-44 `SS-44_ci_pods.png`** — Métricas por pod (los 5 servicios).

**Paso 3 — Dashboard y alarmas**
*CloudWatch → Dashboards → `freshbox-dashboard`*:
📸 **SS-45 `SS-45_dashboard.png`** — Widgets EKS (CPU/memoria/nodos) y RDS.
*CloudWatch → Alarms*:
📸 **SS-46 `SS-46_alarmas.png`** — Alarmas `freshbox-rds-*` (con acción SNS).
*CloudWatch → Log groups* → filtra `containerinsights`:
📸 **SS-47 `SS-47_log_groups_ci.png`** — Log groups `/aws/containerinsights/freshbox-cluster/performance` (y application, dataplane).

> Si Container Insights no muestra datos: `kubectl get pods -n amazon-cloudwatch` y `kubectl -n amazon-cloudwatch logs ds/cloudwatch-agent --tail=30`. Si el Lab bloquea permisos de CloudWatch, documéntalo como restricción (el docente lo permite) y muestra el add-on instalado (SS-23) + `kubectl top`.

---

## FASE 7 — HPA y escalamiento (pods y nodos)

*Sirve para:* **Presentación 2.3** e informe **1.3 (escalabilidad)**.

**Paso 1 — Estado inicial**
```bash
kubectl get hpa -n freshbox
kubectl top pods -n freshbox
kubectl get nodes
```
📸 **SS-48 `SS-48_hpa_inicial.png`** — 5 HPA con `TARGETS` (ej. `3%/70%`), `MINPODS 2`, `MAXPODS 5`, `REPLICAS 2`. (Si dice `<unknown>`, espera 1–2 min: metrics-server está calculando.)

**Paso 2 — Dos pestañas de CloudShell** (botón `+` en CloudShell → *Add new tab*).
- **Pestaña A (observar):**
```bash
kubectl get hpa get-products-hpa -n freshbox -w
```
- **Pestaña B (generar carga controlada, solo sobre get-products):**
```bash
kubectl -n freshbox create deployment load-generator --image=busybox:1.36 --replicas=4 \
  -- /bin/sh -c 'while true; do wget -q -O /dev/null http://get-products:3001/api/products; done'
```

**Paso 3 — Observar el escalamiento de pods (1–3 min)**
En la Pestaña A verás subir `TARGETS` por sobre 70 % y `REPLICAS` pasar de 2 → 3 → 4/5.
📸 **SS-49 `SS-49_hpa_escalando.png`** — HPA con CPU sobre 70 % y réplicas aumentando.
```bash
kubectl get pods -n freshbox -l app=get-products -o wide
```
📸 **SS-50 `SS-50_pods_get_products_5.png`** — Hasta 5 pods `get-products`.

**Paso 4 — Observar el escalamiento de nodos (si faltan recursos)**
Con 5 réplicas puede que algún pod quede `Pending` por falta de capacidad (t4g.small admite ~11 pods por nodo). Entonces el **Cluster Autoscaler** agrega un 4.º nodo (2–5 min):
```bash
kubectl get pods -n freshbox | grep Pending
kubectl -n kube-system get deploy | grep autoscaler
kubectl -n kube-system logs deploy/cluster-autoscaler-aws-cluster-autoscaler --tail=15
kubectl get nodes
```
📸 **SS-51 `SS-51_nodos_escalando.png`** — Logs del autoscaler ("scale-up") y/o 4 nodos. Si no hubo `Pending`, tampoco fue necesario escalar nodos: anótalo y muestra la configuración min 2 / max 4 (SS-21).

📸 **SS-52 `SS-52_ci_cpu_pico.png`** — Container Insights (Fase 6) mostrando el pico de CPU y el aumento de pods durante la carga.

**Paso 5 — Detener la carga y ver el escalado hacia abajo**
```bash
kubectl -n freshbox delete deployment load-generator
```
Espera 2–5 min en la Pestaña A hasta ver `REPLICAS` volver a 2.
📸 **SS-53 `SS-53_hpa_scale_down.png`** — HPA de vuelta a 2 réplicas.

> Qué debes saber explicar: **HPA** escala **réplicas de pods** según CPU (reacciona en segundos/minutos); el **Cluster Autoscaler** escala **nodos** (EC2 del Node Group, entre 2 y 4) cuando los pods no caben. Primero crecen pods, y si no hay espacio, crecen nodos.

---

## FASE 8 — Evidencia de alta disponibilidad y resiliencia

*Sirve para:* informe **1.3** (HA, redundancia) y preguntas de la defensa.

**Paso 1 — Autorreparación de pods**
Pestaña A: `kubectl get pods -n freshbox -l app=get-products -w` · Pestaña B:
```bash
kubectl -n freshbox delete pod -l app=get-products --wait=false
```
Verás cómo Kubernetes recrea los pods; recarga la app: sigue respondiendo (hay 2 réplicas + Service).
📸 **SS-54 `SS-54_pods_autoreparacion.png`** — Pods terminando y recreándose.

**Paso 2 — Failover de RDS Multi-AZ** *(hazlo el día de antes, NO en medio de la defensa; la BD queda ~1–3 min sin responder)*
1. *RDS → freshbox-db → Connectivity & security*: anota la **Availability Zone** actual.
📸 **SS-55 `SS-55_rds_az_antes.png`** — AZ primaria y secundaria antes.
2. *Actions → Reboot* → marca **Reboot with failover** → *Confirm*.
3. Pestaña **Logs & events → Recent events**: aparecen "Multi-AZ instance failover started / completed".
📸 **SS-56 `SS-56_rds_eventos_failover.png`** — Eventos del failover.
4. Cuando vuelva a *Available*, revisa la AZ.
📸 **SS-57 `SS-57_rds_az_despues.png`** — AZ primaria cambiada (la secundaria pasó a ser primaria).
5. Recarga la app y repite un GET: debe funcionar sin cambiar nada (mismo endpoint DNS).
📸 **SS-58 `SS-58_app_ok_post_failover.png`** — Catálogo cargando después del failover.

---

## FASE 9 — Ensayo de la defensa (10 minutos) y cierre

**Paso 1 — Checklist 1 hora antes**
1. Learner Lab **iniciado** (círculo verde). Si el Lab se reinició, **actualiza los 3 secrets** y verifica los recursos.
2. En CloudShell: `kubectl get nodes` (3 Ready) · `kubectl get pods -n freshbox` (10 Running) · `kubectl get ingress -n freshbox` (con ADDRESS).
3. ALB → Target group con targets *Healthy*. La URL abre en el navegador.
4. Si algo quedó caído (por ejemplo, el Lab reinició instancias): Actions → **Redeploy K8s** (pon `rebuild_images = false`). Si faltan recursos de infraestructura: vuelve a ejecutar **Terraform Apply + Deploy EKS** (≈ 40 min, por eso se revisa con tiempo).
5. Deja abiertas estas pestañas, en este orden: PowerPoint · Consola EKS · Consola RDS · Consola ECR · EC2 → Load Balancers · CloudWatch Container Insights · App (URL del ALB) · CloudShell (2 pestañas).

**Paso 2 — Guion de 10 minutos (sugerido por la guía del docente)**

| Min | Contenido | Qué mostrar |
|---|---|---|
| 0:00–1:00 | Problema de FreshBox y por qué modernizar | Diapositiva diagnóstico + SS-04/05 (costos) |
| 1:00–3:00 | Diagrama TO-BE y decisiones (3 capas, SG, flujo ALB→pods→RDS) | SS-03 |
| 3:00–7:00 | Infraestructura + CRUD en vivo | Consola EKS (nodos/addons), `kubectl get pods`, ECR, RDS Multi-AZ (config), ALB targets, CRUD en la app |
| 7:00–9:00 | Escalamiento y monitoreo | Container Insights + HPA (`get hpa -w`) con carga ya iniciada 2 min antes |
| 9:00–10:00 | Conclusiones y limitaciones | Resumen |

Consejos: inicia la carga (Fase 7, paso 2B) **en el minuto 5**, así a los 7–8 min el HPA ya está escalando. Cronometra el ensayo.

**Paso 3 — Qué incluir en el informe (resumen de dónde va cada evidencia)**

| Sección del informe | Evidencias |
|---|---|
| 1.1 Análisis de diferencias | Fase 2 (SS-04, SS-05 + tabla comparativa) |
| 1.2 Estrategia de modernización | Fase 2 (fases de migración) + SS-03 |
| 1.3 Escalabilidad / Seguridad / HA | SS-11–13 (SG), SS-17/24 (cifrado RDS/EBS), SS-16/18 (Multi-AZ), SS-21/22/25 (nodos 2 AZ), SS-48–53 (HPA y nodos), SS-54–58 (resiliencia) |
| Anexo de implementación | SS-06–10, SS-14/15, SS-27–37, SS-38–42, SS-43–47 |

**Paso 4 — Destruir al terminar (solo DESPUÉS de la defensa)**
Actions → **Terraform Destroy** → *Run workflow* → escribe `yes`. Primero elimina el Ingress (para borrar el ALB), luego destruye el resto (≈ 20–30 min). Verifica en consola que no queden NAT Gateways, EKS ni RDS: cuestan créditos del Lab.
Finalmente, **elimina a mano** el bucket `chacon-freshbox-ep2-tfstate` (vacíalo primero) si no lo volverás a usar.

---

## Problemas frecuentes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Error: Failed to get existing workspaces: S3 bucket does not exist` | Falta el bucket del Paso 0.2 o el nombre no coincide | Crear el bucket / corregir `backend.tf` |
| `ExpiredToken` / `InvalidClientTokenId` | Credenciales del Lab vencidas | Actualizar los 3 secrets `AWS_*` y relanzar |
| `InvalidParameterException ... version 1.35` | La versión no está habilitada en tu región/cuenta | Cambia `kubernetes_version` a `1.34` en `variables.tf` **y** `CA_IMAGE_TAG` a `v1.34.0` en `deploy-k8s.sh` (o variable de entorno) |
| `Cannot find version 8.4 for mysql` | Versión no disponible | `db_engine_version = "8.0"` en `variables.tf` |
| Error de `iam:*` / `AccessDenied` en EKS | Academy bloquea crear roles | El proyecto ya usa `LabRole`; no agregues recursos IAM |
| `Unauthorized` al usar kubectl | El cluster lo creó otro principal (el pipeline) | Usa la misma cuenta/Lab; o `aws eks create-access-entry` + `associate-access-policy` con `AmazonEKSClusterAdminPolicy` para tu rol `voclabs` |
| Pods `ImagePullBackOff` | Imagen no existe en ECR | Ver ECR (SS-15); relanzar **Redeploy K8s** con `rebuild_images = true` |
| Pods `CrashLoopBackOff` con `exec format error` | Imagen amd64 en nodos ARM | Las imágenes deben construirse con `--platform linux/arm64` (el script ya lo hace) |
| Pods `Pending` (`Too many pods`) | t4g.small ≈ 11 pods/nodo | Esperar al Cluster Autoscaler o subir `node_desired` a 4 |
| Ingress sin ADDRESS | ALB Controller sin permisos/subredes | `kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50`; revisar tags `kubernetes.io/role/elb` en subredes públicas |
| Targets del ALB `unhealthy` | SG o health check | Revisar SS-12 (80 desde SG-ALB) y que el path sea `/health` |
| Job `db-init` falla | RDS aún creándose / SG | `kubectl -n freshbox logs job/db-init`; relanzar **Redeploy K8s** |
| App muestra error 500 al crear/editar | Backend sin conexión a RDS | `kubectl -n freshbox logs deploy/create-product --tail=30`; revisar SG-RDS (SS-13) |
| Container Insights sin datos | Add-on aún iniciando o permisos | Ver nota de la Fase 6; esperar 10 min |
| `terraform destroy` falla en VPC/SG | Quedó un ALB creado por el Ingress | Borrar `freshbox-chacon-alb` y sus Target Groups desde la consola y reintentar |
