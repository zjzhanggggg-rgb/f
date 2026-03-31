Here’s an update on what I worked on today and my plan for the rest of the week.

Today, I researched best practices for building a standardized CI/CD pipeline that can be reused across different AI agent repositories, while still allowing GitLab pipelines and jobs to be customized for each repo’s specific needs. I also built out a basic structure for the reusable CI repo.

I’m structuring the reusable CI repo in two phases. The first phase focuses on code quality and validation, including standard software checks that should apply to every agent repo, such as schema validation, linting, type checking, and unit tests. The second phase focuses on RAG quality evaluation, including AI-specific checks such as retrieval evaluation, response quality, faithfulness, and deployment gates based on evaluation thresholds.

This approach lets us first standardize the core engineering checks, then add the AI evaluation layer on top in a clean and scalable way.

For the rest of the week, I’m planning to start implementing the first phase, focusing on code quality checks like syntax validation, linting, and type checking.

Once the initial setup is in place, I’ll also create a short user manual explaining how to use the CI/CD setup and the reusable repo. I plan to share it with the AI intern group chat first to gather feedback before rolling it out more broadly.
