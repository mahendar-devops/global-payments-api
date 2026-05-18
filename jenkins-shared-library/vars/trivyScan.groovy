#!/usr/bin/env groovy
// jenkins-shared-library/vars/trivyScan.groovy
//
// Reusable Trivy image scanning step.
// Called from any Jenkinsfile with: trivyScan(imageName: 'payments-service:1.0.0')
//
// Parameters:
//   imageName    (required) Full image name:tag to scan
//   severity     (optional) Comma-separated severities to block on. Default: CRITICAL,HIGH
//   exitCode     (optional) Exit code on failure. Default: 1 (fail build)
//   outputFormat (optional) Output format. Default: table. Options: json, sarif, table
//   ignoreFile   (optional) Path to .trivyignore file. Default: .trivyignore

def call(Map params = [:]) {
    def imageName    = params.imageName    ?: error("trivyScan: 'imageName' parameter is required")
    def severity     = params.severity     ?: 'CRITICAL,HIGH'
    def exitCode     = params.exitCode     ?: 1
    def outputFormat = params.outputFormat ?: 'table'
    def ignoreFile   = params.ignoreFile   ?: '.trivyignore'

    echo "🔍 Running Trivy scan on: ${imageName}"
    echo "   Severity threshold: ${severity}"
    echo "   Exit code on failure: ${exitCode}"

    // Install Trivy if not available (idempotent)
    sh '''
        if ! command -v trivy &> /dev/null; then
            echo "Installing Trivy..."
            curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
                | sh -s -- -b /usr/local/bin v0.50.4
        else
            echo "Trivy already installed: $(trivy --version)"
        fi
    '''

    // Determine ignore file flags
    def ignoreFlag = fileExists(ignoreFile) ? "--ignorefile ${ignoreFile}" : ''

    // Run the scan
    def scanResult = sh(
        script: """
            trivy image \\
                --exit-code ${exitCode} \\
                --severity ${severity} \\
                --format ${outputFormat} \\
                --timeout 10m \\
                ${ignoreFlag} \\
                --no-progress \\
                ${imageName}
        """,
        returnStatus: true
    )

    // Also generate SARIF report for archiving (regardless of exit code)
    sh """
        trivy image \\
            --exit-code 0 \\
            --severity CRITICAL,HIGH,MEDIUM \\
            --format sarif \\
            --output trivy-${env.BUILD_NUMBER}.sarif \\
            --timeout 10m \\
            --no-progress \\
            ${imageName} || true
    """

    // Archive the SARIF report
    if (fileExists("trivy-${env.BUILD_NUMBER}.sarif")) {
        archiveArtifacts artifacts: "trivy-${env.BUILD_NUMBER}.sarif",
                         allowEmptyArchive: true
        echo "📄 Trivy SARIF report archived: trivy-${env.BUILD_NUMBER}.sarif"
    }

    // Fail the build if Trivy found issues above threshold
    if (scanResult != 0) {
        error """
            ❌ Trivy scan FAILED for image: ${imageName}
            Found vulnerabilities at severity: ${severity}
            
            ACTION REQUIRED:
              1. Review the scan output above
              2. Update affected dependencies to patched versions
              3. If no fix is available, add a documented exception to .trivyignore
                 (requires AppSec team approval and expiry date within 90 days)
        """
    }

    echo "✅ Trivy scan passed: no ${severity} vulnerabilities found in ${imageName}"
}
