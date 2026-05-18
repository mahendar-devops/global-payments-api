#!/usr/bin/env groovy
// jenkins-shared-library/vars/notifySlack.groovy
//
// Reusable Slack notification step.
// Sends rich formatted notifications on pipeline success, failure, or custom events.
//
// Usage:
//   notifySlack(status: 'SUCCESS', service: 'payments-service', imageTag: '42-abc1234')
//   notifySlack(status: 'FAILURE', service: 'gateway-service',  stage: 'Trivy Scan')
//   notifySlack(status: 'STARTED', service: 'payments-service')

def call(Map params = [:]) {
    def status    = params.status   ?: 'UNKNOWN'
    def service   = params.service  ?: env.JOB_NAME ?: 'Unknown Service'
    def imageTag  = params.imageTag ?: env.IMAGE_TAG ?: 'N/A'
    def stage     = params.stage    ?: env.STAGE_NAME ?: ''
    def channel   = params.channel  ?: '#deployments-payments'
    def author    = params.author   ?: env.GIT_AUTHOR ?: 'Unknown'

    def buildUrl  = env.BUILD_URL  ?: ''
    def buildNum  = env.BUILD_NUMBER ?: '?'
    def gitBranch = env.GIT_BRANCH  ?: 'N/A'

    // Map status to emoji and Slack colour
    def (emoji, color) = [
        'SUCCESS': ['✅', 'good'],
        'FAILURE': ['🚨', 'danger'],
        'STARTED': ['🔄', '#439FE0'],
        'UNSTABLE': ['⚠️', 'warning'],
        'ABORTED':  ['🛑', '#808080'],
    ].get(status.toUpperCase(), ['❓', '#808080'])

    def title = "${emoji} *${service}* — ${status}"

    def fields = [
        [title: 'Build',    value: "<${buildUrl}|#${buildNum}>", short: true],
        [title: 'Branch',   value: gitBranch,                    short: true],
        [title: 'Image Tag', value: "`${imageTag}`",              short: true],
        [title: 'Author',   value: author,                       short: true],
    ]

    if (stage) {
        fields << [title: 'Failed Stage', value: "`${stage}`", short: true]
    }

    def attachment = [
        color:       color,
        title:       title,
        title_link:  buildUrl,
        fields:      fields,
        footer:      "Jenkins CI | ${new Date().format("yyyy-MM-dd HH:mm:ss")} UTC",
        footer_icon: 'https://www.jenkins.io/images/logos/jenkins/jenkins.svg',
        mrkdwn_in:   ['text', 'fields'],
    ]

    try {
        slackSend(
            channel:     channel,
            color:       color,
            attachments: groovy.json.JsonOutput.toJson([attachment])
        )
    } catch (Exception e) {
        // Slack notification failures must never fail the pipeline
        echo "⚠️ Slack notification failed (non-critical): ${e.message}"
    }
}
