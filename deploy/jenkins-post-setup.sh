#!/bin/bash
# deploy/jenkins-post-setup.sh
#
# Run this script AFTER completing the Jenkins setup wizard.
# It automates the remaining Jenkins system configuration that
# the guide's UI steps cover.
#
# Usage (run from your LAPTOP, not the Jenkins server):
#   bash deploy/jenkins-post-setup.sh \
#       --jenkins-ip YOUR_JENKINS_IP \
#       --jenkins-user admin \
#       --jenkins-pass YOUR_ADMIN_PASSWORD \
#       --app-ip YOUR_APP_SERVER_IP
# ─────────────────────────────────────────────────────────────────
set -e

# ── Parse arguments ───────────────────────────────────────────────
JENKINS_IP=""
JENKINS_USER="admin"
JENKINS_PASS=""
APP_IP=""

while [[ "$#" -gt 0 ]]; do
  case $1 in
    --jenkins-ip)   JENKINS_IP="$2";   shift ;;
    --jenkins-user) JENKINS_USER="$2"; shift ;;
    --jenkins-pass) JENKINS_PASS="$2"; shift ;;
    --app-ip)       APP_IP="$2";       shift ;;
    *) echo "Unknown parameter: $1"; exit 1 ;;
  esac
  shift
done

JENKINS_URL="http://${JENKINS_IP}:8080"
JENKINS_CLI_JAR="/tmp/jenkins-cli.jar"

echo "================================================"
echo "  Jenkins Post-Setup Configuration"
echo "================================================"
echo "Jenkins URL: $JENKINS_URL"
echo ""

# ── Download Jenkins CLI ──────────────────────────────────────────
echo "Downloading Jenkins CLI..."
curl -sf "${JENKINS_URL}/jnlpJars/jenkins-cli.jar" -o "$JENKINS_CLI_JAR"
JCLI="java -jar $JENKINS_CLI_JAR -s $JENKINS_URL -auth ${JENKINS_USER}:${JENKINS_PASS}"

echo "Testing Jenkins CLI connection..."
$JCLI who-am-i && echo "✅ Connected to Jenkins" || {
  echo "❌ Cannot connect to Jenkins. Check IP, credentials, and port 8080 in Security Group."
  exit 1
}

# ── Start SonarQube (if not already running) ──────────────────────
echo ""
echo "Starting SonarQube on Jenkins server..."
ssh -i ~/.ssh/payments-devops -o StrictHostKeyChecking=no ec2-user@"$JENKINS_IP" \
  'docker ps | grep sonarqube || docker run -d \
    --name sonarqube --restart unless-stopped \
    -p 9000:9000 \
    -v sonarqube_data:/opt/sonarqube/data \
    sonarqube:lts-community'

echo "Waiting for SonarQube to start (this takes ~60 seconds)..."
for i in $(seq 1 18); do
  STATUS=$(curl -sf "http://${JENKINS_IP}:9000/api/system/status" 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
  if [ "$STATUS" = "UP" ]; then
    echo "✅ SonarQube is UP"
    break
  fi
  echo "  Waiting... ($((i*10))s)"
  sleep 10
done

# ── Create SonarQube token ────────────────────────────────────────
echo ""
echo "Creating SonarQube analysis token..."
SONAR_RESPONSE=$(curl -sf -u admin:admin -X POST \
  "http://${JENKINS_IP}:9000/api/user_tokens/generate" \
  --data-urlencode "name=jenkins-token" \
  --data-urlencode "type=GLOBAL_ANALYSIS_TOKEN" 2>/dev/null || echo "")

SONAR_TOKEN=$(echo "$SONAR_RESPONSE" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('token',''))" 2>/dev/null || echo "")

if [ -n "$SONAR_TOKEN" ]; then
  echo "✅ SonarQube token created"
  # Add SonarQube token to Jenkins credentials
  $JCLI create-credentials-by-xml system::system::jenkins _ << EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <id>sonarqube-token</id>
  <description>SonarQube Analysis Token</description>
  <secret>${SONAR_TOKEN}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF
  echo "✅ SonarQube token added to Jenkins credentials"
else
  echo "⚠️  Could not auto-create SonarQube token."
  echo "   Manual step: http://${JENKINS_IP}:9000 → admin/admin → Security → User Tokens → Generate"
  echo "   Then add to Jenkins: Manage Jenkins → Credentials → Add → Secret text → ID: sonarqube-token"
fi

# ── Add App Server SSH Key to Jenkins ────────────────────────────
echo ""
echo "Adding App Server SSH key to Jenkins credentials..."
PRIVATE_KEY=$(cat ~/.ssh/payments-devops)

$JCLI create-credentials-by-xml system::system::jenkins _ << EOF
<com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>
  <id>app-server-ssh-key</id>
  <description>App Server SSH Private Key</description>
  <username>ec2-user</username>
  <privateKeySource class="com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey\$DirectEntryPrivateKeySource">
    <privateKey>${PRIVATE_KEY}</privateKey>
  </privateKeySource>
</com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>
EOF
echo "✅ SSH key added to Jenkins credentials"

# ── Add App Server IP to Jenkins ─────────────────────────────────
echo "Adding App Server IP to Jenkins credentials..."
$JCLI create-credentials-by-xml system::system::jenkins _ << EOF
<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <id>app-server-ip</id>
  <description>App Server Public IP</description>
  <secret>${APP_IP}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
EOF
echo "✅ App Server IP added to Jenkins credentials"

# ── Configure SonarQube in Jenkins System Settings ────────────────
echo ""
echo "Configuring SonarQube in Jenkins system settings..."
$JCLI groovy = << 'GROOVY'
import jenkins.model.*
import hudson.plugins.sonar.*
import hudson.plugins.sonar.model.*

def sonarInstallations = [
  new SonarInstallation(
    "SonarQube",                    // Name (referenced in Jenkinsfile)
    "http://localhost:9000",         // URL
    "sonarqube-token",              // Credentials ID
    null, null, null, null, null, null
  )
]

def desc = Jenkins.instance.getDescriptor(SonarGlobalConfiguration.class)
desc.setInstallations(sonarInstallations as SonarInstallation[])
desc.save()
println("✅ SonarQube configured in Jenkins")
GROOVY

# ── Create Pipeline Jobs for all 3 services ───────────────────────
echo ""
echo "Creating Jenkins pipeline jobs..."

for SERVICE in payments-service gateway-service data-processing-service; do
  echo "  Creating pipeline: ${SERVICE}-pipeline"
  $JCLI create-job "${SERVICE}-pipeline" << EOF
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>CI/CD pipeline for ${SERVICE}</description>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
    <scm class="hudson.plugins.git.GitSCM">
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>REPLACE_WITH_YOUR_GITHUB_URL</url>
          <credentialsId>github-token</credentialsId>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec><name>*/main</name></hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>${SERVICE}/Jenkinsfile</scriptPath>
    <lightweight>true</lightweight>
  </definition>
  <triggers>
    <com.cloudbees.jenkins.GitHubPushTrigger/>
  </triggers>
</flow-definition>
EOF
  echo "  ✅ ${SERVICE}-pipeline created"
done

echo ""
echo "================================================"
echo "  Jenkins Post-Setup COMPLETE"
echo "================================================"
echo ""
echo "REMAINING MANUAL STEPS:"
echo "1. Update GitHub URL in each pipeline job:"
echo "   Jenkins Dashboard → each pipeline → Configure → Repository URL"
echo "   Replace: REPLACE_WITH_YOUR_GITHUB_URL"
echo "   With:    https://github.com/YOUR_USERNAME/global-payments-api.git"
echo ""
echo "2. Add GitHub token to Jenkins credentials manually:"
echo "   Manage Jenkins → Credentials → Add → Secret text"
echo "   ID: github-token | Secret: your GitHub Personal Access Token"
echo ""
echo "3. Change SonarQube admin password:"
echo "   http://${JENKINS_IP}:9000 → admin/admin → Profile → Change password"
echo ""
echo "4. Trigger first build:"
echo "   Jenkins Dashboard → payments-service-pipeline → Build Now"
