# CI/CD (Jenkins & GitHub Actions) — fiche mémo

## Jenkinsfile déclaratif

```groovy
pipeline {
  agent any                                    // none | { label 'linux' } | { docker { image 'x'; args '…'; reuseNode true } }
  options { timeout(time: 30, unit: 'MINUTES'); timestamps(); disableConcurrentBuilds(); buildDiscarder(logRotator(numToKeepStr: '20')) }
  parameters { booleanParam(name: 'DEPLOY', defaultValue: false) }
  environment { IMAGE = 'ghcr.io/u/app'; CREDS = credentials('id') }   // CREDS_USR / CREDS_PSW
  stages {
    stage('Test') {
      agent { docker { image 'python:3.12-slim'; reuseNode true } }
      steps { sh 'pytest --junitxml=r.xml' }
      post { always { junit 'r.xml' } }
    }
    stage('Parallèle') { parallel { stage('A') { steps { … } } stage('B') { steps { … } } } }
    stage('Push') {
      when { branch 'main' }                   // changeset 'app/**' · tag 'v*' · expression { … } · allOf/anyOf/not
      steps {
        withCredentials([usernamePassword(credentialsId: 'gh', usernameVariable: 'U', passwordVariable: 'P')]) {
          sh 'echo "$P" | docker login ghcr.io -u "$U" --password-stdin'     // guillemets SIMPLES
        }
      }
    }
  }
  post { always { cleanWs() } failure { … } success { … } }
}
```

`script { env.X = sh(script: 'cmd', returnStdout: true).trim() }` · `archiveArtifacts` · `stash/unstash` · `input` · `waitForQualityGate abortPipeline: true` · `withSonarQubeEnv('sonarqube') { … }`.

## GitHub Actions

```yaml
name: CI
on: { push: { branches: [main], paths: ["app/**"] }, pull_request: {}, workflow_dispatch: {} }
permissions: { contents: read }
concurrency: { group: "ci-${{ github.ref }}", cancel-in-progress: true }
jobs:
  test:
    runs-on: ubuntu-latest
    strategy: { matrix: { python: ["3.11", "3.12"] } }
    steps:
      - uses: actions/checkout@<sha40> # v5
      - uses: actions/setup-python@<sha40> # v6
        with: { python-version: "${{ matrix.python }}", cache: pip }
      - run: pytest
  publish:
    needs: test
    if: github.ref == 'refs/heads/main'
    permissions: { contents: read, packages: write, id-token: write }
    environment: production                    # approbations / secrets d'environnement
    steps: [ … docker/login-action avec secrets.GITHUB_TOKEN … ]
```

Contextes : `github.sha`, `github.ref`, `github.actor`, `secrets.X`, `vars.X`, `env.X`, `steps.<id>.outputs.x`, `needs.<job>.outputs.x`. Écrire une variable : `echo "K=V" >> "$GITHUB_ENV"` ; une sortie : `>> "$GITHUB_OUTPUT"` ; un résumé : `>> "$GITHUB_STEP_SUMMARY"`.
`gh run list / watch / view --log-failed / rerun --failed`.

Sécurité : actions épinglées par SHA · `permissions` minimales · OIDC plutôt que secrets longs · jamais `${{ github.event.* }}` interpolé directement dans `run:`.
