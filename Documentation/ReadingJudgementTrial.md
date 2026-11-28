# General Training Reading 判定問題の試作

同じ対話モデルで、職場の研修案内を題材にした短い英文と判定問題を2組作成した。対象は TRUE / FALSE / NOT GIVEN の設問品質。アプリや外部APIは使用していない。問題数・語数を縮小し、判定に関係する生成指示だけを適用した。

## 現行指示での試作

**Induction sessions**

The depot offers a Tuesday morning induction and a Thursday afternoon induction. Both cover the same material. New starters are normally booked onto Tuesday's session. Anyone who cannot attend their allocated session should email Jo before noon on Monday. Jo will check whether there is space in the other group. Staff do not need to bring a laptop. A paper handbook is issued at the end of each session.

Last month four warehouse assistants asked to move to the Thursday group. Three received confirmation by email on Monday. The fourth assistant was still waiting for a reply when the office closed that evening. For this month's sessions, the depot has arranged for a trainer from the city office to visit on Thursday. Tuesday's session will be led by the depot supervisor as usual.

| # | Statement | 生成時の正答・理由 |
|---|---|---|
| 1 | New employees are generally assigned to the morning group. | TRUE。通常は火曜午前に割り当てられる。 |
| 2 | Employees must supply their own laptop. | FALSE。持参は不要。 |
| 3 | Sending Jo a message guarantees a change of session. | FALSE。変更先に空きがあるかを確認する。 |
| 4 | The afternoon group receives a different handbook from the morning group. | NOT GIVEN。配布物の内容の違いは説明されていない。 |
| 5 | The fourth assistant's request was refused. | NOT GIVEN。月曜の終業時点で返答待ち。 |
| 6 | Staff are given their handbook before the induction begins. | FALSE。配布は終了時。 |
| 7 | The city office trainer is taking the Thursday session this month. | TRUE。木曜に市の事務所から講師が来る。 |
| 8 | Tuesday is the more popular of the two sessions. | NOT GIVEN。通常の割り当ては希望人数を示さない。 |
| 9 | Staff who cannot attend are asked to contact Jo by Monday lunchtime. | TRUE。月曜正午までに連絡する。 |
| 10 | All four assistants had received a response by the time the office closed on Monday. | FALSE。1人はまだ返答待ち。 |

### 本文との照合

判定基準は「本文から主張全体が導ける」「本文が主張を否定する」「成立する場合もしない場合も本文と両立する」の3通り。語の一致だけでは判定しない。同じモデルによる再読で、生成時の答えを独立に隠した実験ではない。

- 1、2、4、5、6、8、10は根拠と正答が対応した。
- 3は要修正。空きの確認は変更が保証されないことを強く示唆するが、確認後の扱いは明記されていない。断る場合があると書けばFALSEを支えられる。
- 7は要修正。訪問目的は推測できるが、訪問者が見学するだけでも本文と矛盾しない。TRUEにするなら担当すると明記する。
- 9は要修正。「正午より前」と「昼食時まで」は締切が一致するとは限らない。厳密に読んだ受験者を不利にする。

## 改訂指示での試作

**Refresher workshops**

Each employee returning to the packing line must complete one refresher workshop. The Wednesday and Friday workshops use the same practical exercise. Supervisors initially assign each employee a date. To request a different date, employees must submit a form before 10 am on Tuesday. A form submitted at exactly 10 am is late. The training office approves a move only if the requested workshop has a vacant place. Employees must attend their original workshop unless the office confirms a change.

Last week six employees asked to move to Friday. The office approved four requests and refused two because the Friday workshop was full by the time those forms were processed. Both employees whose requests were refused attended on Wednesday. A visitor from head office observed Friday's practical exercise. The packing supervisor led that exercise. After it ended, the visitor handed participants a printed checklist. No record was made of who kept their checklist.

| # | Statement | 生成時の正答 | 照合時の根拠・未確定事項 |
|---|---|---|---|
| 1 | Returning packing-line workers have to take a refresher workshop. | TRUE | 対象者全員に研修が必須。 |
| 2 | A request handed in at 10 am on Tuesday meets the deadline. | FALSE | ちょうど10時は遅いと明記。 |
| 3 | An employee waiting for a decision is still expected at the originally assigned workshop. | TRUE | 確認が来るまで元の日程への参加義務が続く。 |
| 4 | Every employee who requested Friday last week was granted a place. | FALSE | 6人中2人は断られた。 |
| 5 | The two unsuccessful applicants completed the practical exercise faster than the other Wednesday participants. | NOT GIVEN | 参加した事実はあるが作業時間の比較はない。 |
| 6 | The two workshop dates offer different practical exercises. | FALSE | 両日で同じ実習を行う。 |
| 7 | The packing supervisor led the practical exercise observed by the visitor. | TRUE | 訪問者と進行役が明記されている。 |
| 8 | At least one Friday participant threw away the checklist. | NOT GIVEN | 配布後に保管した人の記録がない。全員が保管した可能性もある。 |
| 9 | A vacancy in the requested workshop is enough on its own to guarantee approval. | NOT GIVEN | 空席は必要条件。他の条件も調べるかは不明。 |
| 10 | The visitor distributed the checklists before the practical exercise began. | FALSE | 配布は実習終了後。 |

### 再点検と修正

1〜8、10は本文だけでキーを説明できた。9は意図したNOT GIVENと、期限内の提出も必要だからFALSEという読みが競合した。条件が適用される段階を設問に明記して再判定した。

**9（差し替え）** For requests submitted on time, the training office takes length of service into account when deciding whether to approve a move.

**NOT GIVEN**。期限内に提出した人に対象を限定している。空席を確認することは分かるが、勤続年数も考慮するかは本文のどこにも書かれていない。

初稿の要修正は現行指示で3/10、改訂指示で1/10。各条件1セットで、題材と本文が異なり、作問と点検も同じモデルが担当した。この数値は今回のレビュー件数であり、アプリでの改善率を示すものではない。
