# Jenkins Shared Library — Global Payments API

> **Repository:** `global-payments-api/jenkins-shared-library`  
> **Loaded by all pipelines as:** `@Library('payments-shared-lib@main') _`

## Why a Shared Library?

With 15+ microservices each having a `Jenkinsfile`, duplicating the Trivy scan, 
SonarQube analysis, and Slack notification logic 15 times creates a maintenance 
nightmare. When the security team requires a new Trivy flag, it should be one 
change in one place — not 15 PRs.

The Shared Library centralises reusable pipeline logic. Service teams write 
thin `Jenkinsfile`s that call library steps; the library owns the implementation.

## Structure

```
jenkins-shared-library/
├── vars/                          ← Global variables (callable as pipeline steps)
│   ├── trivyScan.groovy           trivyScan(imageName: '...')
│   ├── sonarAnalysis.groovy       sonarAnalysis(projectKey: '...', language: 'java')
│   ├── dockerBuildPush.groovy     dockerBuildPush(serviceName: '...', ...)
│   ├── k8sDeploy.groovy           k8sDeploy(serviceName: '...', ...)
│   └── notifySlack.groovy         notifySlack(status: 'SUCCESS', service: '...')
├── src/
│   └── com/globalpayments/pipeline/
│       └── PipelineUtils.groovy   ← Helper class (image tag generation, etc.)
└── resources/
    └── trivy-config.yaml          ← Trivy scanner configuration
```

## Usage in a Jenkinsfile

```groovy
@Library('payments-shared-lib@main') _

import com.globalpayments.pipeline.PipelineUtils

pipeline {
    agent { kubernetes { ... } }

    environment {
        IMAGE_TAG    = PipelineUtils.buildImageTag(BUILD_NUMBER, GIT_COMMIT)
        ECR_REGISTRY = '123456789.dkr.ecr.eu-west-2.amazonaws.com'
    }

    stages {
        stage('SonarQube') {
            steps {
                sonarAnalysis(
                    projectKey: 'payments-service',
                    language:   'java',
                    sonarToken: credentials('sonarqube-token')
                )
            }
        }

        stage('Docker Build') {
            steps {
                dockerBuildPush(
                    serviceName: 'payments-service',
                    ecrRegistry: env.ECR_REGISTRY,
                    imageTag:    env.IMAGE_TAG,
                    awsRegion:   'eu-west-2'
                )
            }
        }

        stage('Trivy Scan') {
            steps {
                trivyScan(
                    imageName: "${env.ECR_REGISTRY}/payments-service:${env.IMAGE_TAG}",
                    severity:  'CRITICAL,HIGH'
                )
            }
        }

        stage('Deploy') {
            when { branch 'main' }
            steps {
                k8sDeploy(
                    serviceName:  'payments-service',
                    namespace:    'payments',
                    imageTag:     env.IMAGE_TAG,
                    ecrRegistry:  env.ECR_REGISTRY,
                    eksCluster:   'payments-cluster-prod',
                    smokeTestUrl: 'https://payments-internal.bank.com/actuator/health'
                )
            }
        }
    }

    post {
        success { notifySlack(status: 'SUCCESS', service: 'payments-service', imageTag: env.IMAGE_TAG) }
        failure { notifySlack(status: 'FAILURE', service: 'payments-service', stage: env.STAGE_NAME) }
    }
}
```

## Configuring in Jenkins

1. **Jenkins → Manage Jenkins → Configure System → Global Pipeline Libraries**
2. Add library:
   - **Name:** `payments-shared-lib`
   - **Default version:** `main`
   - **SCM:** Git → `https://github.com/your-org/jenkins-shared-library.git`
3. Jenkins agents must have AWS credentials via IRSA (no static keys).
