Hi Huy, here’s an update on what I worked on today and my plan for the rest of the week.

Today, I researched best practices for building a standardized CI/CD pipeline that can be reused across different AI agent repositories, while still allowing GitLab pipelines and jobs to be customized for each repo’s specific needs. I also built out a basic structure for the reusable CI repo today.

I plan to structure the reusable CI/CD repo in two phases. The first phase focuses on code quality and validation, including standard software checks that should apply to every agent repo, such as schema validation, linting, type checking, and unit tests. The second phase focuses on RAG quality evaluation, including AI-specific checks such as retrieval evaluation, response quality, and faithfulness.

For the rest of the week, I plan to continue implement this framework and improving CAD Agent based on Nicolas and his team's feedback.

Once the initial setup is in place, I’ll also create a short user manual explaining how to use the CI/CD setup and the reusable repo. I will share it with the AI intern group chat to gather feedback. Please let me know if you'd like to make any changes. Thanks.
