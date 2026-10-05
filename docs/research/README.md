# Research

Deep dives behind the GitHub issues: what we found, from which sources, and why it points where it does.
They're evidence, not plans. The plan for each lives in its issue, and what got built is in
[concepts.md](../concepts.md) and [decisions.md](../decisions.md). Open the one whose question you're
working on:

- **[Leveling and points](leveling-points.md):** how RPGs and WaniKani pace growth so it feels earned and
  can't be crammed. Built as word stages and levels
  ([#3](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/3), closed); follow-ups in
  [#38](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/38).
- **[Learner data schema](learner-data-schema.md):** a data model for the words a learner has met and
  knows. Built as the learner store
  ([#4](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/4), closed); syncing with the Zenbu
  apps is [#28](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/28).
- **[Age vocabulary data](age-vocabulary-data.md):** where word lists per age come from, and their
  licenses. Japanese and English are built from them; content and permissions are
  [#13](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/13) and
  [#40](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/40).
- **[Learning modes](learning-modes.md):** which kinds of activity Tomo could use, and when
  ([#14](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/14)).
- **[Answer evaluation](answer-evaluation.md):** checking a learner's answer without AI, and when AI is
  worth calling ([#6](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/6),
  [#17](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/17)).
- **[AI models and costs](ai-models-and-costs.md):** which models handle toddler Japanese and what a
  conversation costs ([#7](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/7),
  [#8](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/8)).
- **[Voices](voices.md):** a child-like Japanese voice that can age with Tomo
  ([#5](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/5)).

Four of these predate the size budget and have an allowance in `.github/scripts/check-docs.mjs`: they
may shrink but not grow. New findings on one of those topics go in a new leaf, linked here.
