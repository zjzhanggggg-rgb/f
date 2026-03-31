You provided a unit test framework in the sense that templates/unit-test/template.yml gives consumers:

a standard GitLab unit-test job
dependency installation from requirements.txt
optional test dependency installation
pytest execution
optional coverage via pytest-cov
JUnit XML report upload
So you did provide the pipeline framework for running unit tests.

What you did not provide is:

actual test cases for consumer repos
a shared testing library
a generated tests/ skeleton
assertions for their agent behavior
So the precise answer is:

Yes, you provided the unit-test CI framework
No, you did not provide the unit tests themselves
