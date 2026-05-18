// jenkins-shared-library/src/com/globalpayments/pipeline/PipelineUtils.groovy
//
// Shared utility class for pipeline helpers.
// Import with: import com.globalpayments.pipeline.PipelineUtils

package com.globalpayments.pipeline

class PipelineUtils implements Serializable {

    private final def script

    PipelineUtils(def script) {
        this.script = script
    }

    /**
     * Generate a consistent image tag from build number and Git commit.
     * Format: <buildNumber>-<shortCommit>
     * Example: 142-a3f7c9b
     */
    static String buildImageTag(String buildNumber, String gitCommit) {
        def shortCommit = gitCommit?.take(7) ?: 'unknown'
        return "${buildNumber}-${shortCommit}"
    }

    /**
     * Returns true if the current branch is a production deployment branch.
     * Deployment to prod only happens from 'main' or 'release/*' branches.
     */
    static boolean isDeployableBranch(String branch) {
        return branch == 'main' || branch?.startsWith('release/')
    }

    /**
     * Returns true if this is a feature/PR branch (not deployable to prod).
     */
    static boolean isFeatureBranch(String branch) {
        return branch?.startsWith('feature/') || branch?.startsWith('fix/')
    }

    /**
     * Formats a duration in milliseconds to a human-readable string.
     * e.g. 93000 → "1m 33s"
     */
    static String formatDuration(long milliseconds) {
        def seconds = milliseconds / 1000
        def minutes = (seconds / 60).intValue()
        def secs    = (seconds % 60).intValue()
        return minutes > 0 ? "${minutes}m ${secs}s" : "${secs}s"
    }

    /**
     * Sanitises a branch name for use in Docker image tags.
     * feature/PAY-1234-add-retries → feature-PAY-1234-add-retries
     */
    static String sanitiseBranchName(String branch) {
        return branch?.replaceAll('[^a-zA-Z0-9._-]', '-')?.take(50) ?: 'unknown'
    }

    /**
     * Returns the ECR registry URL for the given AWS account and region.
     */
    static String ecrRegistry(String accountId, String region = 'eu-west-2') {
        return "${accountId}.dkr.ecr.${region}.amazonaws.com"
    }

    /**
     * Validates that required environment variables are set.
     * Throws an error listing all missing variables at once.
     */
    void validateEnvironment(List<String> requiredVars) {
        def missing = requiredVars.findAll { varName ->
            !script.env[varName]
        }

        if (missing) {
            script.error("Pipeline is missing required environment variables: ${missing.join(', ')}")
        }
    }

    /**
     * Safely reads a Jenkins credential as a secret string.
     * Returns null if the credential doesn't exist (rather than throwing).
     */
    String safeCredential(String credentialId) {
        try {
            def result = null
            script.withCredentials([script.string(
                credentialsId: credentialId,
                variable: 'SECRET_VALUE'
            )]) {
                result = script.env.SECRET_VALUE
            }
            return result
        } catch (Exception e) {
            script.echo "⚠️ Credential '${credentialId}' not found: ${e.message}"
            return null
        }
    }

    /**
     * Checks if a Docker image exists in ECR before pulling/scanning.
     */
    boolean ecrImageExists(String registry, String repo, String tag, String region) {
        def result = script.sh(
            script: """
                aws ecr describe-images \\
                    --repository-name ${repo} \\
                    --image-ids imageTag=${tag} \\
                    --region ${region} \\
                    >/dev/null 2>&1 && echo "exists" || echo "missing"
            """,
            returnStdout: true
        ).trim()
        return result == 'exists'
    }
}
