# Pocket Band AI 1.0.0 · ストア申請用資料

## App Store Connectに入力するURL

| 項目 | 公開URL |
|---|---|
| プライバシーポリシー | https://github.com/NakaokaRei/PocketIELTS/blob/main/Documentation/Privacy.md |
| サポート | https://github.com/NakaokaRei/PocketIELTS/blob/main/Documentation/Support.md |

## 日本語の掲載文案

**名称**　Pocket Band AI

**サブタイトル**　General Trainingの英語4技能対策

**キーワード**　英語,リスニング,リーディング,ライティング,スピーキング,英作文,模擬試験,試験対策,CEFR

IELTS General Trainingの4技能を、練習したいパートから。AIが新しい問題を生成し、設問に応じて図やリスニング音声も用意できます。知らない単語は本文から選び、その文での意味をAIに質問できます。

Writingでは手紙やエッセイを書いて講評を受け、SpeakingではAI試験官とリアルタイムで会話できます。4技能の記録がそろうと、正答状況と評価をもとにバンドスコアとCEFRの目安を表示します。スコアは学習用の推定値です。

収録教材はオフラインでも使えます。問題生成とAI解説はChatGPT接続を使用します。任意の音声生成・画像生成・リアルタイム会話には、ご自身のOpenAI APIキーと別途API利用料が必要です。

## English listing draft

**Name**　Pocket Band AI

**Subtitle**　General Training: Four Skills

**Keywords**　listening,reading,writing,speaking,letters,essays,exam,practice,band,CEFR

Practise the four IELTS General Training skills, one part at a time. Generate fresh exercises, add diagrams and listening audio, or select an unfamiliar word to ask what it means in context.

Write letters and essays for feedback, or answer an AI examiner aloud in a realtime conversation. Once you have records in all four skills, see an estimated overall band and CEFR level. These estimates are for practice.

Bundled material works offline. Question generation and AI explanations use your connected ChatGPT account. Optional generated audio, generated images and realtime speaking use your own OpenAI API key and incur separate API charges.

## App Review notes draft

**提出前に**　角括弧を実測・確認した内容で置き換える。実機動画は審査担当者がアクセスできる形で添付する。以下は現行ソースをもとにした下書きのため、提出ビルドで同じ操作ができることを確認する。

1. **Recording and testing.** [Attachment filename or reviewer-accessible video link]. Recorded from launch on [physical device, OS version, build number]. We tested this build on [iPhone and iPad models and OS versions actually tested].
2. **Purpose and audience.** This is a self-study app for English learners preparing for General Training reading, listening, writing and speaking tasks. Learners can practise a single section, understand mistakes and track estimated proficiency over time. Band and CEFR estimates are for personal study.
3. **How to review.** Launch the app and select Home → Offline practice → Reading → a section. Answer the questions and open the answer review to see your score and explanations. No sign-in or sample file is required for this flow. For new exercises, connect ChatGPT in Settings, return to Home and choose a skill and section. Use the answer review to ask the AI tutor about a question. Submit a Writing response for feedback. Optional listening audio, generated figures and realtime Speaking use a separately configured OpenAI API key. Enable the relevant media option in Settings. For realtime Speaking, start a Speaking session and allow microphone access. [Insert tested reviewer access instructions for the online features in App Store Connect.] OpenAI handles external sign-in. There is no separate developer-operated account system. Settings includes ChatGPT sign-out, API key removal and a separate reset for learning data. Answers, recordings and tutor conversations are private to the learner. There is no public posting or user-to-user messaging.
4. **Services and payment.** OpenAI provides ChatGPT authentication, exercise generation, tutoring, feedback and optional speech, image and realtime voice APIs. Apple provides optional private iCloud sync via CloudKit and on-device speech recognition for recorded answers. The app is free and offers no in-app purchases. Use of a personal OpenAI API key is billed separately by OpenAI.
5. **Regions.** [Confirm against the submitted build and selected storefronts.] The app offers the same study flows and bundled exercises across its distribution regions. Interface and explanation language can vary. Online AI features also depend on OpenAI service and account availability.
6. **Materials and rights.** This is an independent educational app. Its proficiency estimates do not confer a qualification. Bundled font licences for Nunito and Zen Maru Gothic are included. [Identify any protected materials or marks used in the final build and listing, and attach applicable permissions. Confirm the provenance of included exercises and visuals.]

**実機録画の順序**　ホーム画面のアイコンから起動し、未ログインでReadingを1問解いて採点・解説を開く。続いてChatGPTの接続、問題生成、設問へのAI質問、音声再生、Writingの講評、Speakingの実際の1往復を見せる。最後に設定で接続解除とデータ削除の場所を示す。APIキー・認証情報・個人のメールアドレスは録画に映さない。

## 提出者が入力・確認する項目

- **審査用アクセス**　外部認証や有料APIを必要とする機能について、審査担当者が試せる専用アカウントまたは審査用の操作方法をApp Review Informationに用意する。秘密情報は公開リポジトリに記載しない。
- **App Privacy**　実際に提供する構成で、OpenAI・Appleの処理や保持条件も含めて回答する。プロフィールの識別子・メール、入力した学習内容、Speaking音声、任意のサポートメールも確認する。端末内だけの処理と端末外に送る処理は[プライバシーポリシー](../Privacy.md)を参照。プライバシーマニフェストは、この回答の代わりにはならない。
- **最終ビルド**　実機でAIに個人データを送る前の説明・明示的な同意、マイク許可、サインアウト、同期・削除を確認する。配信地域、年齢区分、権利情報、契約状況、審査連絡先と配信用ビルドをApp Store Connectで確定する。

[Appleの審査ガイドライン](https://developer.apple.com/app-store/review/guidelines/) · [App Privacyの入力基準](https://developer.apple.com/app-store/app-privacy-details/)
