pipeline {
	agent none
	stages {
		stage('Build') {
			parallel {
				stage('Unix') {
					agent { label 'net-core' }
					stages {
						stage('Frontend') {
							steps {
								sh 'yarn install --frozen-lockfile && yarn build'
							}
						}
						stage('Backend') {
							steps {
								sh 'dotnet build -c Release ASC.Web.slnf'
							}
						}
					}
				}
				stage('Windows') {
					agent { label 'win-core' }
					stages {
						stage('Frontend') {
							steps {
								bat "yarn install --frozen-lockfile && yarn build"
							}
						}
						stage('Backend') {
							steps {
								bat 'dotnet build -c Release ASC.Web.slnf'
							}
						}
					}
				}
			}
		}
		stage('Test') {
			when { expression { return env.CHANGE_ID != null } }
			parallel {
				stage('Unix') {
					agent { label 'net-core' }
					stages {
						stage('Components') {
							steps {
								sh "yarn install --frozen-lockfile && yarn build && cd ${env.WORKSPACE}/packages/components && yarn test:coverage --ci --reporters=default --reporters=jest-junit || true"
							}
							post {
								success {
									junit 'packages/components/junit.xml'
									publishHTML target: [
										allowMissing         : false,
										alwaysLinkToLastBuild: false,
										keepAll             : true,
										reportDir            : 'packages/components/coverage/lcov-report',
										reportFiles          : 'index.html',
										reportName           : 'Unix Test Report'
									]
									publishCoverage adapters: [coberturaAdapter('packages/components/coverage/cobertura-coverage.xml')]
								}
							}
						}
						stage('Files') {
							steps {
								sh "git submodule update --progress --init -- products/ASC.Files/Server/DocStore && dotnet build ASC.Web.slnf && cd ${env.WORKSPACE}/products/ASC.Files/Tests/ && dotnet test ASC.Files.Tests.csproj -r linux-x64 -l \"console;verbosity=detailed\""
							}
						}
					}
				}
				stage('Windows') {
					agent { label 'win-core' }
					stages {
						stage('Components') {
							steps {
								bat "yarn install --frozen-lockfile && yarn build && cd ${env.WORKSPACE}\\packages\\components && yarn test:coverage --ci --reporters=default --reporters=jest-junit || true"
							}
							post {
								success {
									junit 'packages\\components\\junit.xml'
									publishHTML target: [
										allowMissing         : false,
										alwaysLinkToLastBuild: false,
										keepAll             : true,
										reportDir            : 'packages\\components\\coverage\\lcov-report',
										reportFiles          : 'index.html',
										reportName           : 'Windows Test Report'
									]
								}
							}
						}
						stage('Files') {
							steps {
								bat "git submodule update --progress --init -- products\\ASC.Files\\Server\\DocStore && dotnet build ASC.Web.slnf && cd ${env.WORKSPACE}\\products\\ASC.Files\\Tests\\ && dotnet test ASC.Files.Tests.csproj"
							}
						}
					}
				}
			}
		}
		stage('Notify') {
			when { expression { return env.CHANGE_ID != null && env.BUILD_NUMBER == '1' } }
			agent { label 'net-core' }
			options { skipDefaultCheckout() }
			environment {
				Telegram_Token = credentials('telegram_token')
				Chat_Id = credentials('telegram_chat')
			}
			steps {
				sh 'curl -s -X GET -G "https://api.telegram.org/bot$Telegram_Token/sendMessage" --data-urlencode "chat_id=$Chat_Id"  --data "text=CHANGE URL:$CHANGE_URL %0A Build Url: $BUILD_URL %0A Branch Name:$CHANGE_TITLE"'
			}
		}
    }
}