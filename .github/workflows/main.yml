name: Build and Package
on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  detect:
    runs-on: ubuntu-latest
    outputs:
      wrappers: ${{ steps.filter.outputs.wrappers }}
    steps:
      - uses: actions/checkout@v4

      - id: filter
        uses: dorny/paths-filter@v2
        with:
          filters: |
            wrappers:
              - 'wrappers/**'

  build:
    needs: detect
    if: needs.detect.outputs.wrappers == 'true'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: gradle/wrapper-validation-action@v3

      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '21'
          cache: 'gradle'

      - uses: actions/cache@v4
        with:
          path: |
            ~/.gradle/caches
            ~/.gradle/wrapper
          key: ${{ runner.os }}-gradle-${{ hashFiles('**/*.gradle*', '**/gradle-wrapper.properties') }}
          restore-keys: |
            ${{ runner.os }}-gradle-

      - name: Compile Kotlin Wrapper and produce server.kar
        working-directory: wrappers/Kotlin
        run: |
          set -euo pipefail

          if [ -f "./gradlew" ]; then
            chmod +x ./gradlew
            ./gradlew shadowJar
          else
            echo "Error: gradlew not found in $(pwd)"
            ls -la
            exit 1
          fi

          # Find a sensible jar name (prefer -all or -shadow)
          JAR=$(ls -1 build/libs/*.jar 2>/dev/null | grep -E '\-all\.jar$|\-shadow\.jar$' || true)
          if [ -z "$JAR" ]; then
            JAR=$(ls -1 build/libs/*.jar 2>/dev/null | head -n 1 || true)
          fi

          if [ -z "$JAR" ]; then
            echo "Error: no JAR found in build/libs/ after build!"
            echo "Contents of build/libs/:"
            ls -l build/libs/ || true
            exit 1
          fi

          echo "Found JAR: $JAR"
          # create server.jar and then the requested server.kar
          cp "$JAR" server.jar
          cp server.jar server.kar
          echo "Produced wrappers/Kotlin/server.kar"

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: Artifacts
          path: |
            wrappers/Kotlin/server.kar
          if-no-files-found: error
