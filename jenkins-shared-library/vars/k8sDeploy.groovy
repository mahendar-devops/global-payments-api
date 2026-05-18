#!/usr/bin/env groovy
// jenkins-shared-library/vars/k8sDeploy.groovy
//
// Reusable Kubernetes deployment step with automatic rollback on failure.
//
// Usage:
//   k8sDeploy(
//     serviceName:  'payments-service',
//     namespace:    'payments',
//     imageTag:     "${BUILD_NUMBER}-${GIT_COMMIT[0..7]}",
//     ecrRegistry:  '123456789.dkr.ecr.eu-west-2.amazonaws.com',
//     eksCluster:   'payments-cluster-prod',
//     awsRegion:    'eu-west-2',
//     smokeTestUrl: 'https://payments-internal.bank.com/actuator/health'
//   )

def call(Map params = [:]) {
    def serviceName  = params.serviceName  ?: error("k8sDeploy: 'serviceName' required")
    def namespace    = params.namespace    ?: 'payments'
    def imageTag     = params.imageTag     ?: error("k8sDeploy: 'imageTag' required")
    def ecrRegistry  = params.ecrRegistry  ?: error("k8sDeploy: 'ecrRegistry' required")
    def eksCluster   = params.eksCluster   ?: error("k8sDeploy: 'eksCluster' required")
    def awsRegion    = params.awsRegion    ?: 'eu-west-2'
    def smokeTestUrl = params.smokeTestUrl ?: ''
    def rolloutTimeout = params.rolloutTimeout ?: '5m'

    def fullImage = "${ecrRegistry}/${serviceName}:${imageTag}"

    echo "🚀 Deploying ${serviceName} → EKS cluster: ${eksCluster}"
    echo "   Image: ${fullImage}"
    echo "   Namespace: ${namespace}"

    // Configure kubectl
    sh """
        aws eks update-kubeconfig \\
            --region ${awsRegion} \\
            --name ${eksCluster}
    """

    // Annotate with deployment metadata (audit trail in K8s events)
    sh """
        kubectl annotate deployment/${serviceName} \\
            -n ${namespace} \\
            kubernetes.io/change-cause="Build:${env.BUILD_NUMBER} Image:${imageTag} By:Jenkins" \\
            --overwrite
    """

    // Set the new image
    sh """
        kubectl set image deployment/${serviceName} \\
            ${serviceName}=${fullImage} \\
            -n ${namespace}
    """

    // Wait for rollout — on failure, automatically roll back
    def rolloutStatus = sh(
        script: """
            kubectl rollout status deployment/${serviceName} \\
                -n ${namespace} \\
                --timeout=${rolloutTimeout}
        """,
        returnStatus: true
    )

    if (rolloutStatus != 0) {
        echo "❌ Rollout FAILED — initiating automatic rollback..."

        sh """
            kubectl rollout undo deployment/${serviceName} -n ${namespace}
            kubectl rollout status deployment/${serviceName} -n ${namespace} --timeout=3m || true
        """

        // Capture pod logs for diagnosis
        def podLogs = sh(
            script: """
                kubectl logs -l app=${serviceName} -n ${namespace} \\
                    --previous --tail=100 2>/dev/null || echo 'No previous logs available'
            """,
            returnStdout: true
        ).trim()

        error """
            ❌ Deployment FAILED and has been rolled back automatically.
            
            Service: ${serviceName}
            Failed image: ${fullImage}
            Namespace: ${namespace}
            
            Last 100 log lines:
            ${podLogs}
            
            Next steps:
              1. Review the logs above for the root cause
              2. Fix the issue in a new commit
              3. Re-run the pipeline
        """
    }

    echo "✅ Rollout complete: ${serviceName} updated to ${imageTag}"

    // Smoke test (optional)
    if (smokeTestUrl) {
        echo "🧪 Running smoke test: ${smokeTestUrl}"
        def smokeStatus = sh(
            script: """
                for i in \$(seq 1 5); do
                    STATUS=\$(curl -sf -o /dev/null -w "%{http_code}" \\
                        --max-time 10 "${smokeTestUrl}" 2>/dev/null || echo "000")
                    echo "Attempt \$i: HTTP \$STATUS"
                    if [ "\$STATUS" = "200" ]; then
                        echo "✅ Smoke test passed"
                        exit 0
                    fi
                    sleep 10
                done
                echo "❌ Smoke test failed after 5 attempts"
                exit 1
            """,
            returnStatus: true
        )

        if (smokeStatus != 0) {
            echo "❌ Smoke test failed — rolling back..."
            sh "kubectl rollout undo deployment/${serviceName} -n ${namespace}"
            error "Smoke test failed for ${serviceName}:${imageTag}. Rolled back to previous version."
        }

        echo "✅ Smoke test passed for ${serviceName}"
    }

    return fullImage
}
