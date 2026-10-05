# Age vocabulary data: what Tomo says and understands at each age

> **Status (2026-10-06): the Japanese CDI data from Wordbank is now Tomo's Japanese word list up to 3さい, and NINJAL's 幼児語彙 and 絵本語彙 cover 3–6さい** (`mac-demo/scripts/build-levels.py ja`; [decisions.md](../decisions.md)). Before a beta ships it, we ask the J-CDI developers ([#40](https://github.com/serpcompany/zenbujapanese-tomo-app/issues/40)).

Research for the open question in [concepts.md](../concepts.md). Licenses were checked on official pages on 2026-10-03. Anything not checked is marked **unverified**.

## Answer

Build Tomo's age lists from three sources that allow commercial use, and map every word to a Language Reference ID through JMdict:

1. **Ages 1–3: the Japanese CDI data in Wordbank (CC BY 4.0).** It gives per-word understanding and speaking by month for about 900 children.
2. **Ages 3–6: NINJAL's preschool-speech and picture-book word lists (CC BY 4.0).**
3. **Baby talk: JMdict's own "children's language" and "onomatopoeic/mimetic" tags.** These are already licensed in the monorepo.

Grammar by age comes from the same CDI data up to age 3 (particles, verb endings, two-word stage). After 3 it comes from published milestones (utterance length, question words).

Ages 4–6 are the weak spot. The best per-word source, Mochizuki & Ota's age-of-acquisition ratings, publishes its *article* under CC BY but its *data* under **CC BY-NC**. CHILDES is CC BY-NC-SA and explicitly bars use in commercial products and LLMs. So we either license Mochizuki & Ota or run our own small rating study for 4–6.

At runtime, give the model the age's word list and grammar profile, then check every line with Sudachi before Tomo says it. If a line fails, regenerate once, then fall back to a scripted line.

## Sources

### Usable now

| Source | What it has | Ages | Size | License | Commercial use? |
|---|---|---|---|---|---|
| [Wordbank](https://wordbank.stanford.edu/): Japanese CDI data (Hagihara et al. 2023 merged dataset) | Per-child checklists. **Words & Gestures** form: understands/says for 448 words. **Words & Sentences** form: says for 711 words, plus 25 particles, 30 verb endings, 37 "simple vs. complex sentence" pairs, and the two-word stage. A 幼児語 category gives 41 baby words with adult equivalents (ブーブー（車）). | 8–19 mo (understand + say); 16–42 mo (say) | 316 + 575 children | CC BY 4.0 (Wordbank FAQ; dataset metadata says `CC-BY`) | **Yes** for the data. The word list itself is the J-CDI instrument; ask its developers before shipping it verbatim (**unverified** whether that's needed) |
| NINJAL [幼児語彙](https://mmsrv.ninjal.ac.jp/bev/) (Okubo & Kawamata 1982) | 2,774 words used by 4 preschoolers in everyday speech, with counts per child | Preschool (exact ages **unverified**) | 2,774 words | CC BY 4.0 | **Yes** |
| NINJAL [絵本語彙](https://mmsrv.ninjal.ac.jp/bev/) (Nakasone & Kawamata 1994) | Picture-book words with frequency and number of stories (681 words appear in 10+ stories) | Read-aloud ages | 6,710 words | CC BY 4.0 | **Yes** |
| NINJAL [教科書語彙](https://mmsrv.ninjal.ac.jp/bev/) and [連想語彙表](https://mmsrv.ninjal.ac.jp/rensougoi/) | Lower-elementary textbook words; children's word associations by category | 6+ | Not counted | CC BY 4.0 | **Yes** |
| JMdict tags (local copy in the monorepo) | 145 entries tagged children's language (`chn`), 1,338 tagged onomatopoeic/mimetic (`on-mim`) | n/a | See left | CC BY-SA 4.0 | **Yes** (already used; credit on an About screen) |

NINJAL's policy is CC BY 4.0 for downloadable datasets "whether the purpose is commercial or not," with case-by-case exceptions ([policy PDF](https://www.ninjal.ac.jp/ninjal_wp/wp-content/uploads/2022/05/license-policy-cpcr20220401.pdf)).

### Blocked or reference only

| Source | What it has | Ages | License | Commercial use? |
|---|---|---|---|---|
| [Mochizuki & Ota 2025](https://www.frontiersin.org/journals/language-sciences/articles/10.3389/flang.2025.1605224/full) | 1,345 adults rated the age of acquisition of 5,736 words on a 7-point scale (1 = 0–1 y, 2 = 2–3 y, 3 = 4–5 y, 4 = 6–7 y …) | 0–12+ | Article CC BY; **data on [OSF](https://osf.io/fawmq/) is CC BY-NC 4.0** | **No (blocker)** unless the authors grant a license |
| [CHILDES Japanese](https://talkbank.org/childes/access/Japanese/): 11 corpora (Hamasaki, Ishii, MiiPro, Miyata, NINJAL-Okubo, Noji, Ogawa, Okayama, Ota, PaidoJapanese, Yokoyama) | Transcribed child speech. Okayama has 130 children aged 2;2–4;11; MiiPro follows 4 children from 1;2 to 5;0. | 0–7 | CC BY-NC-SA 3.0; the [rules](https://talkbank.org/0share/rules.html) bar incorporating the data into commercial products, including LLMs | **No (blocker).** Read published findings only |
| J-CDI forms and norms (Ogura & Watamaki 2004, 京都国際社会福祉センター) | Paper questionnaires, manual and norm tables | 8–36 mo | All rights reserved. The [MB-CDI board](https://mb-cdi.stanford.edu/adaptations.html) says each adaptation's developers control its distribution | **No** without permission |
| NINJAL reports 66 and 69 ([幼児の語彙能力](https://repository.ninjal.ac.jp/records/1274) 1980, [連想語彙表](https://repository.ninjal.ac.jp/records/1276) 1981) | Tests of preschoolers' understanding of 220 verbs, 26 adjectives and 46 time/space words | Preschool | Free to read; copyright stays with the holder ([repository guideline](https://www.ninjal.ac.jp/ninjal_wp/wp-content/uploads/2025/10/ninjal-repository-guideline20250401.pdf)) | Reference only (the 連想語彙表 *data* is CC BY, above) |
| NTT (Kobayashi) vocabulary-checklist app data | Parent-reported first words | 0–3 | Not publicly downloadable (**unverified**) | No |
| Kindergarten curriculum ([MEXT 幼稚園教育要領](https://www.mext.go.jp/a_menu/shotou/new-cs/youryou/you/nerai.htm)) | Goals for the 言葉 area only | 3–6 | n/a | No official kindergarten word list exists. The picture-book and textbook lists are the best stand-ins |

## Vocabulary size by age

"Data" numbers were computed by us from Wordbank's raw Japanese files ([langcog/wordbank](https://github.com/langcog/wordbank/tree/master/raw_data)): the median child in each 3-month band, and the words that at least half of the children know. Checklist counts undercount real vocabulary once children near the 711-word ceiling, at about 30 months.

| Tomo age | Understands (data) | Says (data) | Proposed Tomo list sizes, say / understand |
|---|---|---|---|
| 1さい (12–23 mo) | Median 27 words at 12–14 mo, 108 at 15–17, 177 at 18–20 (out of 448). Half of children understand 146 words by 20 mo. | Median 1 word at 12–14 mo, 10 at 15–17, 45 at 18–20, 136 at 21–23. Half of children say 6 words by 17 mo (ワンワン, パパ, ママ, バイバイ, ばあ, アンパンマン) and 79 by 23 mo. | ~80 / ~300 |
| 2さい (24–35 mo) | Not measured (the form only asks about speaking) | Median 282 at 24–26 mo, 401 at 30–32, 521 at 33–35 (out of 711). Half say 574 words by 35 mo. | ~550 / ~1,000 |
| 3さい | Not measured | Median 586 of 711 at 36–41 mo (near the ceiling). The four NINJAL preschoolers used 693–1,596 different words each in recorded speech, which is a lower bound. | ~1,000 / ~2,000 |
| 4–6さい | No open data | No open data. "About 3,000 words by 6" is widely repeated but **unverified** | 1,500 / 2,000 / 2,500 say; understand 2–3× that (assumption) |

Two rules of thumb from the data:

- Understanding runs about 6 months ahead of speaking (52 words understood by half of children at 17 mo, vs. 79 said by half at 23 mo).
- At 15–20 months a child understands about 10× as many words as they say.

For scale, sixth graders know a median of 19,267 words (self-report; [Fujita et al. 2020](https://anlp.jp/proceedings/annual_meeting/2020/pdf_dir/E1-3.pdf)).

## Grammar and utterance milestones

Particles and verb forms are listed once at least 50% of children use them (J-CDI data, as above). Utterance length is measured in morphemes (MLU) and comes from [Miyata, Otomo & Nishizawa 2005](https://aska-r.repo.nii.ac.jp/record/7286/files/0026001200503008023.pdf), which studied only 4 children. Question words are the ages they first appeared in one child (Okubo 1967, table reproduced in [Murasugi 2015](https://www.ic.nanzan-u.ac.jp/LINGUISTICS/staff/murasugi_keiko/pdf/murasugi2015.pdf)). First appearance is not mastery.

| Age | Length | Particles | Verb forms | Questions |
|---|---|---|---|---|
| 1さい | One word. 65% combine two words by 21–23 mo | None reach 50%. ね (39%) and の (35%) are emerging at 21–23 mo | None reach 50% | なに, どこ (1;8); だれ (1;11) |
| 2さい | ~1.5 morphemes at 2;0, ~2.3 at 2;6 | の, ね, と, も, て by 24–26 mo; が, は, に, よ, って, か, かな, 〜てから by 30–32 mo | る, た, たい by 24–26 mo; ない by 27–29 mo; よう ("let's"), じゃない by 30–32 mo | どれ (2;1), どう/どんな (2;3), **どうして from 2;5, used "habitually" by 2;6: the first なんで phase** |
| 3さい | ~3.0 at 3;0; 3.4–3.8 at 3;6. Clauses start to chain with conjunctions in the 3s | を, で, だけ, のに by 33–35 mo; しか, から ("from") by 36+ mo | ます, です, なかった, たかった by 33–35 mo; causative, passive and potential at 55–61% by 36–44 mo | なぜ (3;0) |
| 4さい | Morpheme counts stop being reliable above ~3.5 | No open data | No open data | いくら (4;0); second なに phase (4;2); **second どうして phase (4;3): real "why" questions to learn things**; いつ, どの (4;10) |
| 5–6さい | No open norms found | ので is still rare at 3 (17%); allow it from 5 (assumption) | Hand-author | Hand-author with a native preschool teacher |

## Proposed pipeline

1. **Pin the sources.** Use the monorepo's pattern ([JLPT source record](../../../zenbujapanese-monorepo/apps/ios/LanguageData/Sources/JLPT-Waller-2025-08-26.source.json)): snapshot URL, retrieval date, SHA-256, license and attribution. Start with Wordbank, the NINJAL lists and the JMdict tags.
2. **Map to Language Reference IDs.**
   - Normalize each headword: katakana to a hiragana reading, strip glosses like アオ（青）, and keep the part of speech as a hint.
   - Match JMdict on reading + written form + part of speech.
   - Take `LRID = sha256("edrdg.jmdict\0" + ent_seq)[:16]`, the monorepo's existing mapping policy.
   - Send ambiguous matches (はし) to a review queue. Never guess.
3. **Give each lemma a `say_age` and an `understand_age`, with the evidence.**
   - J-CDI: the month when half of children say or understand the word.
   - 幼児語彙: words used by 2+ of the 4 children are "say" at 4さい; words used by one child are "understand".
   - 絵本語彙: words in 10+ stories are "understand" at 3–4.
   - Fill gaps with one rule. Production evidence only: understand one age band earlier. Input evidence only (books, textbooks): say one band later. In practice, **Tomo's understand-list at age N is roughly its say-list at N+1.**
4. **Build a baby-talk map** from child form to adult LRID (ワンワン → いぬ), using the 41 J-CDI baby words and JMdict `chn`.
   - Give each pair a switch age. The data shows the gap: half say ワンワン by 17 mo, but 犬 only by 23 mo.
   - Block-list the vulgar entries (several `chn` entries are crude).
   - The demo's "grown-ups say: いぬ（犬）" card already fits this model.
5. **Write a grammar profile per age** from the table above: allowed particles, verb endings, question words and a length cap.
6. **Human review.** A native speaker (ideally a preschool teacher) reviews each age pack and adds modern words (スマホ, ユーチューブ).
7. **Ship one versioned age pack per age**, keyed by LRID, so progress can sync with the Zenbu app.

## Runtime enforcement

- **Prompt:** Tomo's age, the grammar profile, the say-list (or its most common part, if long), today's review words, and at most one new word.
- **Check every generated line before Tomo says it:**
  1. Kana only.
  2. Tokenize with Sudachi, Zenbu's tokenizer, and map each lemma to an LRID.
  3. Every content word is on the age's say-list, or is a word the learner just said that Tomo understands (kids echo).
  4. Particles and verb endings are in the age's grammar profile.
  5. Length is within the age cap. Starting points to tune: 2 words at 1さい, 4 at 2さい, 8 at 3さい.
  6. **New-word budget:** at most one word per visit from the next age's list. Log it so it comes back for review, which matches "at most one new word" in [leveling-points.md](leveling-points.md).
- **On failure:** regenerate once and name the bad words ("Tomo doesn't know 会社"). If that also fails, use a scripted line. Log every violation to tune the lists.
- **Understanding the learner:** tokenize their reply the same way. If it has content words outside Tomo's understand-list, Tomo answers ん？ わかんない, even when the AI understood. See [answer-evaluation.md](answer-evaluation.md).

## Risks and open questions

- **Licensing blockers.** Mochizuki & Ota data (NC), CHILDES (NC-SA, no LLMs) and the J-CDI forms can't ship. Next steps:
  - Ask Mochizuki & Ota for a commercial license.
  - Ask the J-CDI developers whether an age list derived from the CC BY Wordbank data is fine.
- **Thin data for 4–6.** Without the AoA ratings, run our own study: about 10 Japanese parents or preschool teachers rate about 3,000 candidate words ("would a 4/5/6-year-old say this? understand it?"). We would own the result.
- **Dated or biased data.** The NINJAL lists come from 1970s–90s speech and books. Wordbank flags the Japanese datasets as non-norming samples, and the checklist hits its ceiling after ~30 months.
- **Baby pronunciation (おいちい, ちゅき) is a speech style, not vocabulary.** Handle it in a style layer, not the word lists.
- **Open:** should Tomo match the median child or one a bit ahead? Should the understand-list be strict? How much of the list fits in the prompt?
- **Unverified:** the ages of the four 幼児語彙 children (the paper is a scanned PDF), and NHK's target ages for its kids' shows.

## Flavor: shows and books

- Shows by age: いないいないばあっ! (0–2, per the [NHK Foundation catalog](https://nhk-fdn.or.jp/int/en/catalog/educational/detail_social/so_peek-a-boo01.html)), おかあさんといっしょ (2–4) and みいつけた! (4–6; both **unverified** on nhk.jp).
- Books: seed topics from the 絵本語彙 frequency list (ねこ, おかあさん, おうさま, おばあさん) rather than from title lists.

## Sources

- Wordbank: [site and license](https://langcog.github.io/wordbank-datapage/), [FAQ](https://langcog.github.io/wordbank-datapage/faq.html), [Japanese raw data and dataset metadata](https://github.com/langcog/wordbank/tree/master/raw_data); Frank et al. 2017, *J. Child Language* 44(3); Hagihara et al. 2023, [OSF s5ydw](https://doi.org/10.17605/osf.io/s5ydw)
- MB-CDI: [adaptations policy](https://mb-cdi.stanford.edu/adaptations.html), [copyright](https://mb-cdi.stanford.edu/copyright.html)
- Mochizuki & Ota 2025, *Frontiers in Language Sciences* 4, [doi:10.3389/flang.2025.1605224](https://doi.org/10.3389/flang.2025.1605224); data license via the [OSF API](https://api.osf.io/v2/nodes/fawmq/)
- TalkBank: [ground rules](https://talkbank.org/0share/rules.html), [CHILDES Japanese corpora](https://talkbank.org/childes/access/Japanese/)
- NINJAL: [dataset index](https://mmsrv.ninjal.ac.jp/), [幼児語彙・絵本語彙](https://mmsrv.ninjal.ac.jp/bev/), [連想語彙表](https://mmsrv.ninjal.ac.jp/rensougoi/), [教育基本語彙](https://mmsrv.ninjal.ac.jp/brfvep/), [license policy](https://www.ninjal.ac.jp/ninjal_wp/wp-content/uploads/2022/05/license-policy-cpcr20220401.pdf); Okubo & Kawamata 1982, [doi:10.15084/00001315](https://doi.org/10.15084/00001315); Nakasone & Kawamata 1994, [doi:10.15084/00002616](https://doi.org/10.15084/00002616)
- JMdict: [EDRDG license](https://www.edrdg.org/edrdg/licence.html); local copy `zenbujapanese-monorepo/apps/ios/LanguageData/Sources/JMdict_e-2026-08-10.gz`
- Miyata, Otomo & Nishizawa 2005, 医療福祉研究 1 ([PDF](https://aska-r.repo.nii.ac.jp/record/7286/files/0026001200503008023.pdf)); Miyata et al. 2013, "Developmental Sentence Scoring for Japanese," *First Language* 33(2), [doi:10.1177/0142723713479436](https://doi.org/10.1177/0142723713479436)
- Murasugi 2015, 幼児の疑問文獲得における三つの特徴 ([PDF](https://www.ic.nanzan-u.ac.jp/LINGUISTICS/staff/murasugi_keiko/pdf/murasugi2015.pdf)), reproducing Okubo 1967, 『幼児言語の発達』
- Fujita, Kobayashi et al. 2020, 小・中・高校生の語彙数調査 ([PDF](https://anlp.jp/proceedings/annual_meeting/2020/pdf_dir/E1-3.pdf))
- MEXT, [幼稚園教育要領 第2章](https://www.mext.go.jp/a_menu/shotou/new-cs/youryou/you/nerai.htm)
