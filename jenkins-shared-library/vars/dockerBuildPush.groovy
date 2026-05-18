#!/usr/bin/env groovy
// jenkins-shared-library/vars/dockerBuildPush.groovy
//
// Reusable Docker build and ECR push step.
// Handles: multi-stage build, tagging, ECR login, push, cleanup.
//
// Usage:
//   dockerBuildPush(
//     serviceName:  'payments-service',
//     ecrRegistry:  '123456789.dkr.ecr.eu-west-2.amazonaws.com',
//     imageTag:     "${BUILD_NUMBER}-${GIT_COMMIT[0..7]}",
//     awsRegion:    'eu-west-2',
//     contextDir:   '.',               // Optional, defaults to '.'
//     dockerfile:   'Dockerfile'       // Optional, defaults to 'Dockerfile'
//   )

def call(Map params = [:]) {
    def serviceName  = params.serviceName  ?: error("dockerBuildPush: 'serviceName' required")
    def ecrRegistry  = params.ecrRegistry  ?: error("dockerBuildPush: 'ecrRegistry' required")
    def imageTag     = params.imageTag     ?: error("dockerBuildPush: 'imageTag' required")
    def awsRegion    = params.awsRegion    ?: 'eu-west-2'
    def contextDir   = params.contextDir   ?: '.'
    def dockerfile   = params.dockerfile   ?: 'Dockerfile'

    def fullImage    = "${ecrRegistry}/${serviceName}:${imageTag}"
    def latestImage  = "${ecrRegistry}/${serviceName}:latest"
    def gitCommit    = env.GIT_COMMIT ?: 'unknown'
    def buildTime    = sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()

    echo "🐳 Building Docker image: ${fullImage}"

    // Build
    sh """
        docker build \\
            --build-arg BUILD_VERSION=${imageTag} \\
            --build-arg GIT_COMMIT=${gitCommit} \\
            --build-arg BUILD_TIMESTAMP=${buildTime} \\
            --label "org.opencontainers.image.created=${buildTime}" \\
            --label "org.opencontainers.image.revision=${gitCommit}" \\
            --label "org.opencontainers.image.version=${imageTag}" \\
            -t ${fullImage} \\
            -t ${latestImage} \\
            -f ${contextDir}/${dockerfile} \\
            ${contextDir}
    """

    echo "📦 Image built successfully: ${fullImage}"

    // Push (ECR login using IRSA — no static credentials)
    sh """
        aws ecr get-login-password --region ${awsRegion} \\
            | docker login --username AWS --password-stdin ${ecrRegistry}
        
        docker push ${fullImage}
        docker push ${latestImage}
    """

    echo "✅ Image pushed: ${fullImage}"

    // Cleanup local image to free disk space on the build agent
    sh """
        docker rmi ${fullImage} ${latestImage} || true
    """

    // Return the full image reference for downstream stages
    return fullImage
}
