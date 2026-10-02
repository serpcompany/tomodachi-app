# Research: a better Japanese voice for Tomo

Checked 2026-10-03. Prices and licenses come from official pages on that date. Quality ratings (naturalness, child-likeness, pitch accent) are **expected values, not a listening test**. Nobody has listened to the candidates side by side yet.

## Answer

Stop using live macOS TTS for the scripted lines. Stages 1–2 currently have 27 unique lines (153 characters in `TomoGame.swift`), so **pre-render them as audio files**, one set per age, and hand-check the pitch accent of every clip. For the MVP, generate both the clips and the live 3さい+ replies with **VOICEVOX**, using one child-like character. VOICEVOX is free, works offline, lets you edit the accent of each mora, and its library (VOICEVOX CORE, MIT) and voice models may be embedded in an app, as long as the app shows a credit such as `VOICEVOX:ずんだもん`. Tomo can "age" by raising or lowering pitch and speed, or by switching to an older-sounding style or character. Later, hire an adult voice actor who specializes in small-child roles, record Tomo at each age, and train our own "Tomo voice" model on those recordings. The contract must explicitly allow that training. Apple voices are adult voices, and the macOS license forbids recording them for commercial use. Cloud voices have no Japanese child voice. ElevenLabs restricts child-like voices.

## Recommendation

**Next step for the demo (about one day)**
1. Run a listening test. Render the same 10 lines (ワンワン！, まんま たべる, ちがう〜, おおきく なった！…) with 3 VOICEVOX child-like voices (ずんだもん, 猫使ビィ, 櫻歌ミコ), one AivisSpeech model, Azure `ja-JP-NanamiNeural` with raised pitch, and Gemini-TTS with a "small child" style prompt. Ask a native speaker to rate child-likeness and accent.
2. Pre-render the 27 stage 1–2 lines with the winner, at 1さい and 2さい settings. Bundle them in the app and play the file when one exists. Keep `AVSpeechSynthesizer` as the fallback for unscripted lines.

**MVP**
- Pre-render every fixed line, including praise and reactions (いたい！, ん？ わかんない…), once per age.
- Generate live 3さい+ AI replies on-device with **VOICEVOX CORE**, using the same character so the clips and live speech sound like one voice. CORE ships a macOS/iOS `xcframework` (release 0.17.0, 2026-08-13).
- Put the credit in the About screen. If the chosen character is famous (ずんだもん is), either pick a less recognizable voice or accept that Tomo will sound like someone else's mascot.
- Fallback if VOICEVOX fails the listening test: Azure ja-JP neural ($0.015 per 1k characters). Its SSML can set kana with accent marks and raise the pitch, but it needs a network connection and it isn't a child voice.

**Later: a custom "Tomo voice"**
1. Hire an adult actor who voices small children; this avoids recording a real child. The contract should cover use in the app **and** training a synthetic voice.
2. Record the scripts at each age (1–5), plus a few hours of read speech.
3. Train one speaker with one style per age. Candidates: Style-Bert-VITS2 or AivisSpeech (best Japanese tooling, but AGPL issues, see Risks) or Qwen3-TTS (Apache-2.0).
4. Ship the model inside the app, or as an Apple speech-synthesis extension (macOS 13+/iOS 16+). The extension makes Tomo's voice usable through `AVSpeechSynthesizer`. Apple doesn't allow network access in these extensions, so it is offline by design.

## Options compared

Price is per 1,000 characters. "Ages?" means whether one voice can be made to sound older or younger.

| Option | Natural | Child-like | Pitch accent | Latency | Offline | Price / 1k chars | Commercial macOS/iOS app | Ages? |
|---|---|---|---|---|---|---|---|---|
| **Apple AVSpeech** (Kyoko/Otoya) | Low–Med | Low (adult voices only) | Med, no per-word control | Instant | Yes | Free | Live API use only. Recording or redistributing System Voices commercially is forbidden | `pitchMultiplier` 0.5–2.0 and rate only |
| **VOICEVOX** (CORE + voice models) | Med–High | **High** for some voices (ずんだもん is described as "子供っぽい高めの声") | **Editable per mora** (`'` accent marks, user dictionary) | Local (speed not measured) | Yes | Free | Yes, with credit. Some characters need company pre-approval or are non-commercial | `pitchScale` / `speedScale` / `intonationScale`, or switch character |
| **AivisSpeech** (Style-Bert-VITS2 models) | High (expected) | Depends on model; we didn't vet a child model | Med; changing `pitchScale` can lower quality | Local; ~900 MB first download | Yes | Free | Engine LGPL-3.0. Models are per-model: ACML allows commercial use and redistribution; ACML-NC doesn't | Switch model or style (pitch shifting discouraged) |
| **COEIROINK** | Med–High | Some voices | Editable | Local | Yes | Free | Pre-rendered audio only, with credit. **Can't embed the software or its models** | Switch character |
| **Style-Bert-VITS2** (self-trained) | High (expected) | Whatever we train | Med–High | Local | Yes | Free | Code AGPL-3.0; JP-Extra base model tagged AGPL-3.0 | Styles per age |
| **Kokoro-82M** | Low for Japanese (author grades C+ to C−) | Low | Low–Med | Fast, small | Yes | Free | Apache-2.0 | Pitch only |
| **Qwen3-TTS 1.7B** | Unverified for Japanese | Possible via a "voice design" text prompt | Unverified | Heavy (1.7B parameters) | Yes | Free | Apache-2.0 | Prompt per age |
| **OpenAI** gpt-4o-mini-tts / tts-1 | Med (OpenAI says voices are "optimized for English") | Prompt only, unverified | Unverified | Network, streams | No | tts-1 $0.015, tts-1-hd $0.03; mini-tts priced per token ($0.60/1M text in, $12/1M audio out) | Yes. Users must be told the voice is AI | Prompt |
| **Google** Chirp 3 HD / Neural2 / Gemini-TTS | High | No ja-JP child voice | Good by default (expected); accent control unverified | Network, streams | No | Chirp 3 HD $0.03, Neural2 $0.016, WaveNet/Standard $0.004; Gemini 2.5 Flash TTS ≈ $0.015 per audio minute | Standard cloud terms | Chirp 3 HD speed 0.25–2×; Gemini style prompts |
| **Azure** ja-JP neural | High | **No ja-JP child voice** (child voices exist only for de, en-GB, en-US, es-MX, fr, it, pt-BR, zh-CN) | **Kana + accent marks in SSML** | Network | No | Neural $0.015, Neural HD $0.022 (East US) | Standard cloud terms | SSML pitch/rate |
| **Amazon Polly** ja-JP | Med | No (child voices are English-only) | Med | Network | No | Standard $0.004, Neural $0.016 | Standard cloud terms | Pitch only partly supported |
| **ElevenLabs** | High (expected) | **Child-like voices can't go in the Voice Library**; policy risk | Unverified | v4 Turbo ~100 ms | No | v4 $0.08 (promo $0.022 until Oct 12), v4 Turbo / Flash $0.04 | Paid plan (Starter and up) | Prompt or voice |
| **Voice actor recordings** | Highest | Highest | Highest (native speaker, directed) | Zero | Yes | Session fee (unverified, get quotes) | Whatever the contract says | Record each age |

## Details

**Apple.** Enhanced and premium voices (premium needs macOS 13 / iOS 16) are voices "that you must download to use". Users get them in System Settings → Accessibility → Read & Speak → System voice. We found no API that lets an app download a voice or bundle one of Apple's; an app can only check `quality` and tell users what to do. Siri voices aren't available to `AVSpeechSynthesizer` (WWDC20). This Mac has only the compact Kyoko and the novelty Eloquence voices, so it's unverified which Japanese enhanced or premium voices exist. All of them are adult voices. The macOS Tahoe license forbids "recording, publishing or redistribution" of System Voices "in a… commercial context". **So Apple voices can't be used to pre-render Tomo's clips.**

**VOICEVOX.** It has three parts:
- The editor app: its terms forbid redistributing it.
- The engine: an LGPL-3.0 local HTTP server on port 50021. It runs on macOS.
- **CORE**: an MIT library with prebuilt files for macOS and iOS.

The voice models' terms allow commercial use and "アプリケーションに組み込んで再配布" (embedding them in an app and redistributing). Generated audio must follow each character's own terms. For ずんだもん, the credit `VOICEVOX:ずんだもん` goes on the app's intro or info screen. Dropping the credit costs ¥400,000 plus tax per character. Political, religious, misleading and adult uses are banned. Characters with extra conditions: 青山龍星, もち子さん and 後鬼 (companies must get pre-approval), Voidoll (corporate use needs an inquiry), ぞん子 (commercial use needs an inquiry), and No.7 and ユーレイちゃん (non-commercial unless pre-approved). Pitch accent can be fixed by hand with AquesTalk-style kana (`ワ'ンワン`), which suits hand-checked clips.

**AivisSpeech.** It uses the same API as VOICEVOX. The software itself needs no credit. Its models come from AivisHub, each under its own license. ACML allows commercial use and redistribution, makes credit optional, and accepts apps where users type arbitrary text as long as the developer makes a reasonable effort to prevent misuse. ACML-NC is non-commercial. The first launch downloads about 250 MB of model plus about 650 MB of BERT, which is too big to embed casually.

**COEIROINK.** Its terms forbid redistributing the software or its models, forbid running the models outside the COEIROINK engine, and require a credit (`COEIROINK:名前`). Learners would have to install COEIROINK themselves, so it is only usable for pre-rendering.

**Other open models.** Fish Audio S2 Pro is under a non-commercial research license, so it's out. Qwen3-TTS (Apache-2.0, supports Japanese, designs a voice from a text description) suits offline pre-rendering on a dev machine, not running inside the app.

**Cloud.** None of the listed ja-JP voices is a child voice: Google (30 Chirp 3 HD, Neural2 B–D, WaveNet and Standard A–D), Azure (8 standard plus HD and MAI voices) or Polly (Mizuki, Takumi, Kazuha, Tomoko). Gemini-TTS supports ja-JP (GA) with style prompts. ElevenLabs says child-like voices "cannot be added to the Library". Its use policy also bars "material designed to impersonate a minor" in its child-safety section. Cost isn't the deciding factor: rendering all 153 characters × 5 ages × 3 takes costs under $0.20, even at $0.08 per 1k.

## Pre-rendering vs live TTS

| | Pre-rendered (TTS or actor) | Live TTS |
|---|---|---|
| Latency | Zero | Local: small. Cloud: a network round trip |
| Pitch accent | Checked by hand, line by line | Whatever the engine guesses |
| Ages | One clip set per age | Parameters or voice switching |
| Covers AI replies | No | Yes |
| Size | Tiny (27 short clips today) | Engine and model (VOICEVOX model size unverified) |

Use both, like the existing "check offline first, AI for leftovers" rule: pre-render everything fixed, and use live TTS only for open-ended 3さい+ replies. The live voice must match the clips, which is why the MVP uses the same VOICEVOX character for both. The "later" path trains a model on the actor's own voice for the same reason.

## Listening side (speech recognition)

- **Apple:** on this Mac (macOS 27.2), `SFSpeechRecognizer(ja-JP).supportsOnDeviceRecognition` returned `true`. The new `SpeechTranscriber` (macOS/iOS 26+) lists `ja_JP` as supported but not yet installed. `contextualStrings` (up to 100 short phrases) and custom language models (macOS 14+) can bias recognition toward the expected answers, which Tomo always knows.
- **Whisper-class models:** the openai/whisper code is MIT; large-v3 is Apache-2.0 and large-v3-turbo is MIT. They run on-device via WhisperKit (MIT) or whisper.cpp (MIT). kotoba-whisper v2.0 is a Japanese-specific model under Apache-2.0. `initial_prompt` can bias toward expected words. The cost is size and battery.
- **Accented learner speech:** we found no verified benchmark. Strong language models tend to "fix" learner errors, which fits our rule ("grade whether you were understood") but may be too lenient. Record about 50 learner clips and compare Apple (with `contextualStrings`) against WhisperKit before choosing.

## Risks and open questions

- No listening test yet; every quality rating above is an expectation.
- Only the ずんだもん-group terms (zunko.jp) were read in full. Other characters' full terms, and the terms for the VOICEVOX ONNX Runtime binaries, were not checked.
- ずんだもん is a well-known character, so brand confusion is likely.
- It's unclear whether fine-tuning the AGPL-3.0 Style-Bert-VITS2 base model makes our weights AGPL. Ask a lawyer, or use Apache-2.0 Qwen3-TTS.
- Restrictions on child-sounding voices at providers other than ElevenLabs are unverified. Telling users the voice is AI is good practice everywhere, not just at OpenAI.
- Voice-actor cost and consent to AI training are unknown; get quotes.
- Whether the Mac App Store sandbox allows launching a local engine as a subprocess is unverified. Embedding CORE as a library avoids the question.

## Sources (checked 2026-10-03)

- Apple: [AVSpeechSynthesisVoiceQuality](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality), [.premium](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoicequality/premium), [pitchMultiplier](https://developer.apple.com/documentation/avfaudio/avspeechutterance/pitchmultiplier), [AVSpeechSynthesisProviderAudioUnit](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovideraudiounit), [WWDC20 10022](https://developer.apple.com/videos/play/wwdc2020/10022/), [WWDC23 10033](https://developer.apple.com/videos/play/wwdc2023/10033/), [Mac voice settings](https://support.apple.com/guide/mac-help/change-the-voice-your-mac-uses-to-speak-text-mchlp2290/mac), [macOS Tahoe license §2F](https://www.apple.com/legal/sla/docs/macOSTahoe.pdf)
- VOICEVOX: [software terms](https://voicevox.hiroshiba.jp/term/), [characters](https://voicevox.hiroshiba.jp/), [voice model terms](https://github.com/VOICEVOX/voicevox_vvm), [CORE (MIT) and releases](https://github.com/VOICEVOX/voicevox_core/releases), [ENGINE (LGPL-3.0, accent notation)](https://github.com/VOICEVOX/voicevox_engine), [ずんだもん terms](https://zunko.jp/con_ongen_kiyaku.html)
- AivisSpeech: [Engine README](https://github.com/Aivis-Project/AivisSpeech-Engine), [ACML 1.0](https://github.com/Aivis-Project/ACML/blob/master/ACML-1.0.md)
- COEIROINK: [terms](https://coeiroink.com/terms), [download](https://coeiroink.com/download)
- Open models: [Style-Bert-VITS2](https://github.com/litagin02/Style-Bert-VITS2), [JP-Extra base](https://huggingface.co/litagin/Style-Bert-VITS2-2.0-base-JP-Extra), [Kokoro voices](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md), [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign), [Fish Audio S2 Pro](https://huggingface.co/fishaudio/s2-pro)
- OpenAI: [pricing](https://developers.openai.com/api/docs/pricing), [TTS guide](https://developers.openai.com/api/docs/guides/text-to-speech)
- Google: [pricing](https://cloud.google.com/text-to-speech/pricing), [voices](https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types), [Chirp 3 HD](https://docs.cloud.google.com/text-to-speech/docs/chirp3-hd), [Gemini-TTS](https://docs.cloud.google.com/text-to-speech/docs/gemini-tts)
- Azure: [voices](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts), [ja-JP phonemes](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-ssml-phonetic-sets), [pricing page](https://azure.microsoft.com/en-us/pricing/details/cognitive-services/speech-services/) (numbers from the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices), East US)
- Amazon Polly: [voices](https://docs.aws.amazon.com/polly/latest/dg/available-voices.html), [pricing](https://aws.amazon.com/polly/pricing/)
- ElevenLabs: [API pricing](https://elevenlabs.io/pricing/api), [plans](https://elevenlabs.io/pricing), [models](https://elevenlabs.io/docs/overview/models), [child-like voices](https://elevenlabs.io/docs/help-center/product/voices/voice-library/can-childrens-or-child-like-voices-be-added-to-the-voice-library), [use policy](https://elevenlabs.io/use-policy)
- Speech recognition: [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [contextualStrings](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings), [SFSpeechLanguageModel](https://developer.apple.com/documentation/speech/sfspeechlanguagemodel), [Whisper](https://github.com/openai/whisper), [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift), [whisper.cpp](https://github.com/ggml-org/whisper.cpp), [kotoba-whisper](https://huggingface.co/kotoba-tech/kotoba-whisper-v2.0)
