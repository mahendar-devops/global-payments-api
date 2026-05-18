# ✅ Pre-Lab Checklist — Global Payments API
## Read This BEFORE Starting the Deployment Lab

This document answers: **"Am I ready to start? What will break if I skip this?"**

---

## 🟢 WHAT YOU HAVE (Already Complete)

| Item | File Location | Status |
|------|--------------|--------|
| payments-service source (Java) | `payments-service/` | ✅ Complete |
| gateway-service source (Node.js) | `gateway-service/` | ✅ Complete |
| data-processing-service source (Python) | `data-processing-service/` | ✅ Complete |
| Jenkinsfiles (all 3, EC2-adapted) | `*/Jenkinsfile` | ✅ Complete |
| Dockerfiles (all 3, multi-stage) | `*/Dockerfile` | ✅ Complete |
| SonarQube properties (all 3) | `*/sonar-project.properties` | ✅ Complete |
| Terraform free-tier infrastructure | `infra/free-tier/` | ✅ Complete |
| Bootstrap script (S3 + DynamoDB) | `infra/free-tier/bootstrap.sh` | ✅ Complete |
| Production Docker Compose | `deploy/docker-compose.prod.yml` | ✅ Complete |
| Environment variable templates | `deploy/.env.prod` | ✅ Complete |
| Nginx config (SSL + headers) | `deploy/nginx/payments-api.conf` | ✅ Complete |
| Prometheus config (app server) | `deploy/monitoring/prometheus.yml` | ✅ Complete |
| Jenkins post-setup script | `deploy/jenkins-post-setup.sh` | ✅ Complete |
| Ansible hardening playbook | `infra/ansible/` | ✅ Complete |
| Jenkins Shared Library | `jenkins-shared-library/` | ✅ Complete |
| Deployment Guide (HTML) | `GlobalPaymentsAPI_DeploymentGuide.html` | ✅ Complete |

---

## 🔴 KNOWN CONSTRAINTS — Read Before Starting

### 1. t2.micro Has Only 1GB RAM
**Problem:** Java (Maven) builds consume ~800MB RAM during compilation.
With 6+ Docker containers running, the app server needs headroom.

**Solution — ALREADY HANDLED:** The Terraform `user_data` bootstrap scripts
automatically create **2GB of swap space** on both EC2 instances at launch.
You don't need to do anything extra — just wait 5 minutes after `terraform apply`
for the bootstrap to complete before SSHing in.

**How to verify swap is active:**
```bash
ssh jenkins
free -h
# Should show: Swap: 2.0G total
```

---

### 2. Docker Network Name Must Match
**Problem:** The Jenkinsfiles reference `--network global-payments-api_payments-net`.
This is the network name Docker Compose creates. If your project folder is named
differently, the network name changes.

**Solution:** Always run Docker Compose from this exact folder name:
```bash
mkdir -p ~/global-payments-api
cd ~/global-payments-api
# Put docker-compose.prod.yml here as docker-compose.yml
docker-compose up -d
```
Docker names the network: `<folder-name>_payments-net` → `global-payments-api_payments-net`.

**How to verify the network name:**
```bash
docker network ls | grep payments
# Should show: global-payments-api_payments-net
```

---

### 3. Services Must Start in This Order
**Problem:** payments-service depends on Postgres and Kafka. gateway-service
depends on payments-service. Starting them all at once causes startup failures.

**Solution — ALREADY HANDLED:** `deploy/docker-compose.prod.yml` has `depends_on`
with `condition: service_healthy` for each service. Docker Compose handles the order.

**How to verify order is correct:**
```bash
docker-compose ps
# Watch: postgres starts → kafka starts → payments-service starts → gateway starts
```

---

### 4. Spring Boot Takes ~90 Seconds to Start on t2.micro
**Problem:** The smoke test in the Jenkinsfile runs immediately after deploy.
Spring Boot + limited CPU = slow startup.

**Solution — ALREADY HANDLED:** The payments-service Jenkinsfile has `sleep 60`
before the smoke test, and the Docker Compose `healthcheck` has `start_period: 90s`.

---

### 5. SonarQube Default Admin Password
**Problem:** SonarQube ships with `admin/admin`. Bots scan for default credentials.

**Solution:** Change immediately after first login:
```
http://YOUR_JENKINS_IP:9000 → Login: admin / admin
Top right: admin → My Account → Security → Change Password
```

---

### 6. GitHub Token vs Password
**Problem:** GitHub stopped accepting passwords for git push in 2021.

**Solution:** You need a Personal Access Token (PAT):
1. GitHub.com → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Generate new token → Select scope: `repo` (full control)
3. Copy the token → use it as the "password" when git push asks

Add the same token to Jenkins:
- Manage Jenkins → Credentials → Add → Secret text → ID: `github-token`

---

### 7. Certbot Requires a Real Domain
**Problem:** Let's Encrypt cannot issue certificates for IP addresses.
You need a domain name pointed at your server.

**Options (cheapest first):**

| Option | Cost | Time |
|--------|------|------|
| Free subdomain (afraid.org/freedns) | $0 | 10 min |
| Freenom .tk domain | $0 | 15 min |
| .dev domain (Namecheap/Porkbun) | ~$10/year | 5 min |

**For LinkedIn:** A real domain like `payments-api.yourname.dev` looks significantly
more professional than a free subdomain.

**Minimum DNS record needed:**
```
Type: A
Name: api (or @)
Value: YOUR_APP_SERVER_PUBLIC_IP
TTL: 300
```

---

### 8. ECR is Not Used in Free-Tier Version
**Explanation:** The original architecture uses AWS ECR (Elastic Container Registry).
For the free-tier lab, the Jenkinsfiles use `docker save` + `scp` instead — this
pipes the Docker image directly to the app server without needing ECR.

**Tradeoff:** Slightly slower (transfers ~200-500MB per build), but zero additional
cost and simpler setup. ECR is available and configured in the full Terraform modules
(`infra/modules/ecr/`) if you want to add it later.

---

## 📋 EXACT ORDER TO FOLLOW

```
Step 1:  Run terraform bootstrap
         cd microservices/infra/free-tier
         bash bootstrap.sh

Step 2:  Fill in terraform.tfvars
         - your_home_ip (get with: curl https://checkip.amazonaws.com)
         - state_bucket (already filled by bootstrap.sh)

Step 3:  Generate SSH key pair
         ssh-keygen -t rsa -b 4096 -C "your@email.com" -f ~/.ssh/payments-devops
         aws ec2 import-key-pair --key-name payments-devops \
           --public-key-material fileb://~/.ssh/payments-devops.pub --region eu-west-2

Step 4:  Run Terraform
         terraform init -backend-config=backend.hcl
         terraform plan -var-file=terraform.tfvars
         terraform apply -var-file=terraform.tfvars
         # Note the IPs printed at the end

Step 5:  Wait 5 minutes (bootstrap scripts running on EC2)
         Then verify: ssh -i ~/.ssh/payments-devops ec2-user@JENKINS_IP
         Check swap: free -h  (should show 2G swap)

Step 6:  Complete Jenkins setup wizard
         http://JENKINS_IP:8080
         - Install suggested plugins
         - Create admin user

Step 7:  Run jenkins-post-setup.sh
         bash deploy/jenkins-post-setup.sh \
           --jenkins-ip JENKINS_IP \
           --jenkins-user admin \
           --jenkins-pass YOUR_PASS \
           --app-ip APP_IP

Step 8:  Set up App Server
         ssh -i ~/.ssh/payments-devops ec2-user@APP_IP
         cd ~/global-payments-api
         # Copy deploy/docker-compose.prod.yml as docker-compose.yml
         # Copy deploy/.env.prod as .env (fill in secrets)
         # Copy deploy/monitoring/prometheus.yml to monitoring/prometheus.yml
         docker-compose up -d

Step 9:  Get a domain + SSL
         Point DNS A record → APP_IP
         sudo certbot --nginx -d api.YOURDOMAIN.com \
           --non-interactive --agree-tos -m your@email.com

Step 10: Push code to GitHub → webhook triggers pipeline → watch it build!
         git push origin main
```

---

## 🧪 VALIDATION COMMANDS — Run These to Confirm Everything Works

```bash
# From your laptop — replace IPs and domain

# 1. Terraform outputs look correct
cd microservices/infra/free-tier && terraform output

# 2. Both EC2 instances are running
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=GlobalPaymentsAPI" \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],State.Name,PublicIpAddress]' \
  --output table --region eu-west-2

# 3. Swap is active on Jenkins
ssh jenkins "free -h | grep Swap"

# 4. Docker is running on both servers
ssh jenkins "docker ps"
ssh appserver "docker ps"

# 5. All 6 containers running on app server
ssh appserver "docker-compose -f ~/global-payments-api/docker-compose.yml ps"

# 6. Payments service health
curl http://APP_IP:8080/actuator/health

# 7. Gateway service health
curl http://APP_IP:3000/health/liveness

# 8. HTTPS working (replace with your domain)
curl https://api.YOURDOMAIN.com/health

# 9. Jenkins pipeline ran successfully
# Check at: http://JENKINS_IP:8080

# 10. SonarQube shows all 3 projects
# Check at: http://JENKINS_IP:9000
```

---

## 💰 Free Tier Usage — Stay Within Limits

| Resource | Free Tier Limit | Our Usage | Buffer |
|----------|----------------|-----------|--------|
| EC2 t2.micro | 750 hrs/month each | 2 instances × 744 hrs | Tight — stop when not in use |
| EBS (SSD) | 30 GB/month | 30GB + 20GB = 50GB | ⚠️ Over limit — gp3 is cheap though |
| S3 | 5 GB storage | <100MB | Plenty |
| DynamoDB | 25 GB storage | <1MB | Plenty |
| Data Transfer | 1 GB/month outbound | Depends on usage | Monitor |

**Cost tip:** Stop EC2 instances when not practicing:
```bash
# Stop (not terminate — keeps your data)
aws ec2 stop-instances --instance-ids JENKINS_ID APP_ID --region eu-west-2

# Start again later
aws ec2 start-instances --instance-ids JENKINS_ID APP_ID --region eu-west-2
```

**Set AWS Budget Alert at $5** (Section 03 of the deployment guide).

---

## 🎯 WHAT "DONE" LOOKS LIKE

When everything is working, you should have:

1. ✅ `https://api.YOURDOMAIN.com/health` returns `{"status":"UP"}`
2. ✅ `https://api.YOURDOMAIN.com/api/v1/payments` (unauthenticated) returns `401 Unauthorized`
3. ✅ Jenkins shows all 3 pipelines with green (SUCCESS) status
4. ✅ SonarQube shows all 3 projects with Quality Gate: Passed
5. ✅ Grafana dashboard at `http://APP_IP:3001` shows live metrics
6. ✅ SSL padlock visible in browser for your domain
7. ✅ `git push origin main` triggers pipelines automatically

**If all 7 are true → you're ready to share your LinkedIn post!**
