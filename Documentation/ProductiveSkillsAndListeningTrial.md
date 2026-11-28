# Listening・Speaking・Writing の教材と採点の点検

同梱教材、公開された試験官コメント、この場のモデルによる小規模な試作を使用した。公式答案の採点は公開点を見た上での照合で、アプリの採点モデルのブラインド評価は行っていない。

## Listening

同梱の4パート40問で、根拠として保存されていた引用と正答を台本に照合した。例えばPart 1の予約金の設問では、従来の引用が金額を言う直前で切れていた。Part 4の台帳の設問3問には同じ導入部分が引用されていた。各問の決め手を含む箇所に差し替えた。各引用が台本に1回だけ現れ、同じ発話に収まり、設問順に登場することを機械的にも確認した。

試作した発話は “The van is booked for nine. That’s when we load it. Passengers should meet us at half past nine.”。乗客の集合時刻を問うなら9:30、積み込み開始時刻なら9:00になる。最初の文だけを集合時刻の根拠にすると誤る。新しい指示では最終的な答えを確定する語句を引用する。

## Speaking

同梱のPart 2は個人的な旅の経験を述べるカード、Part 3は交通の信頼性や移動手段の選択を議論する構成。試作では、Part 1で最近の買い物、Part 2で品物を修理した経験と結果、Part 3で買い替えより修理を選ぶ条件を扱った。単独で生成したPart 3でも問いの対象が分かるようにした。

Part 3の問い “When is repairing an appliance a better choice than replacing it?” に対する短い回答を比較した。

- “Repair is good because it is good for people.” は立場を示すが、理由が循環していて比較条件が分からない。
- “If only the hinge has broken, replacing the whole fridge wastes money. But if the motor keeps failing, buying a newer model might cost less in the long run.” は二つの状況を比較し、理由と条件節の使用を確認できる。

後者の方がこの問いへの説明は発展している。どちらの文字起こしからも発音や間の長さは判定できず、数文から試験全体のバンドは確定できない。公開されているKatsuharuのPart 3の例でも、個人的経験から一般論への展開は文字起こしで検討できる。公開の総合点には音声に基づく判断も含まれる。[IELTS公式の発話例と試験官コメント](https://ielts.org/organisations/ielts-for-organisations/understanding-ielts-scoring/resources-for-setting-your-ielts-scores)

## Writing

公式General TrainingのTask 1Aで、試験官はScript Aに5.5、Bに7を付けている。どちらも個室への変更を求めており、Bにも文法ミスがある。違いを説明するには、依頼の背景、段落間のつながり、誤りが読み手に与える影響を見る必要がある。Task 2BのScript A（4）では、買い物の具体例はあっても、なぜ人気なのかという設問に答えていない点が指摘されている。[IELTS公式の答案・講評](https://ielts.org/cdn/Sample-tests/ielts-general-training-writing-sample-tasks-2023.pdf)

試作したTask 1は、研修担当者に日程変更の手紙を書き、参加予定の研修、理由、代替日を伝えるもの。理由と研修名が同じ答案で、結びを “Please help me.” から “Could I attend the Thursday session instead?” に変えると、代替日を求める要件が満たされる。この一文だけで語彙・文法まで一律に加点する根拠はない。

試作したTask 2は、公共施設に修理窓口を置く利点と欠点を論じ、自分の立場を示すもの。費用削減だけを詳しく述べた答案は、英文が正確でも欠点を扱ったことにはならない。新しい採点指示ではこの欠落をTask Responseの講評に明示する。

計算例では、4観点の平均がTask 1で6.25、Task 2で6.75。各タスクの表示値に先に丸めると、重み1対2で合成した結果が7.0になる。平均を保持して重み付けした値は約6.58で、アプリの0.5刻みの表示は6.5。これはアプリ内の集計の回帰テストで、採点モデルの予測精度とは別に検証できる。[IELTS公式のWriting形式と重み](https://ielts.org/take-a-test/test-types/ielts-general-training-test/ielts-general-training-format-writing)
