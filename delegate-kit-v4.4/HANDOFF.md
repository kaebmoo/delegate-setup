# HANDOFF: ชุดไฟล์ /delegate (Claude วางแผนและตรวจรับ, Codex เขียนโค้ด)

เอกสารนี้สำหรับ Claude เซสชันถัดไป (Cowork) และสำหรับผู้ใช้ ใช้ต่องานจากจุดที่ค้างโดยไม่ต้องอ่านบทสนทนาเดิม

## 1. สิ่งที่ทำเสร็จแล้ว

| ไฟล์ | หน้าที่ |
|---|---|
| `delegate/SKILL.md` | คำสั่ง `/delegate` ระดับผู้ใช้ (v4) มีวงจร preflight, plan, slice loop, review, finish และ resume |
| `delegate/delegate-run.sh` | (v4) สคริปต์ผู้ช่วย: เรียก Codex แทนโมเดล, ทำ ledger และเพดานจำนวนครั้ง, lock, เพดานเวลา, ตรวจ status.md กับของจริง (`version`, `codex`, `count`, `check-status`) |
| `tests/run_tests.sh` | (v4.1) ชุดทดสอบ 61 ข้อของสคริปต์ด้วย Codex ปลอม ไม่ใช้เครือข่าย รันได้ทั้ง Linux และ macOS: `bash tests/run_tests.sh` |
| `VERSION` | ชื่อรุ่นของชุดไฟล์ (ใช้ตรวจว่าเครื่องผู้ใช้ได้ไฟล์รุ่นล่าสุด) |
| `settings.snippet.json` | ค่า permissions (allow/deny) และ env สำหรับ `~/.claude/settings.json` |
| `repo-templates/AGENTS.md` | แม่แบบกติกาของ repo ที่ทั้ง Codex และ Claude อ่าน |
| `repo-templates/CLAUDE.md.snippet` | import `@AGENTS.md` และกติกา "เรียก Codex เฉพาะเมื่อพิมพ์ /delegate" |
| `merge-settings.js` | รวม `settings.snippet.json` เข้า `~/.claude/settings.json` ด้วย Node: สำรองไฟล์เดิม, ไม่ลบหรือทับรายการเดิม, ทำซ้ำได้โดยไม่เพิ่มซ้ำ, ถ้า JSON เดิมเสียจะไม่แตะอะไร (มี `--dry-run`) |
| `install.sh` | ติดตั้ง `SKILL.md` และ `delegate-run.sh` ไปที่ `~/.claude/skills/delegate/` โดยไม่ลบ ไม่แตะ settings.json ถ้ามีไฟล์ใดต่างกันและไม่ใช้ `--force` จะไม่เปลี่ยนอะไรเลยแม้แต่ไฟล์เดียว (exit 2) |

## 2. การตัดสินใจออกแบบและเหตุผล

- **ทุกรอบเรียก `codex exec` ใหม่ด้วย brief ไฟล์ใหม่ ไม่ใช้ `resume`** ทดสอบกับ CLI จริงแล้วพบว่า `codex exec resume` ไม่มี `--sandbox` และไม่มี `--cd` จึงยืนยันไม่ได้ว่า sandbox คงเดิม วิธีนี้ยังตรวจสอบย้อนหลังได้ทุกรอบ
- **`.ai/` ซ่อนตัวเองด้วย `.ai/.gitignore` ที่มีบรรทัด `*`** แทนการแก้ `.git/info/exclude` เพราะไม่ต้องแตะ `.git` (ซึ่ง Claude Code ถือเป็น protected path และจะถามสิทธิ์) และใช้ได้กับ git worktree ทดสอบแล้ว
- **ถามยืนยันครั้งเดียวต่อ repo ก่อนส่งโค้ดให้ Codex** (ไฟล์ `.ai/external-ok`) เพราะ Codex อ่านไฟล์แล้วส่งเนื้อหาไป OpenAI ซึ่งย้อนคืนไม่ได้
- **ตรวจ `codex login status` จากข้อความ ไม่ใช่ exit code** เพราะทดสอบแล้วได้ exit 0 แม้พิมพ์ "Not logged in"
- **เพดานเวลา (v4):** สคริปต์ `delegate-run.sh` จับเวลาเองด้วย `--timeout-sec` (ไม่พึ่งคำสั่ง `timeout` ซึ่ง macOS ไม่มี) ส่ง TERM แล้วรอสูงสุด 5 วินาทีก่อนใช้ KILL และ Bash timeout ของ Claude Code ตั้งเป็นเพดานนอกที่ใหญ่กว่า 60 วินาที Codex ที่ยังไม่ล็อกอินจะค้างเงียบ ๆ ไม่ error (ทดสอบแล้ว) skill จึงถือว่าไม่มีไฟล์ผลลัพธ์เท่ากับ BLOCKED
- **Claude แก้เองได้เฉพาะ mechanical fix** (ไม่เกิน 5 บรรทัด, ไม่เปลี่ยนพฤติกรรม, บันทึกใน review) ตั้ง `CLAUDE_MECHANICAL_FIXES=deny` ถ้าต้องการความเป็นอิสระของผู้ตรวจเต็มรูปแบบ
- **เพดาน:** 3 รอบต่อชุดงาน, 12 การเรียก Codex ต่อหนึ่งรอบ /delegate (v4: สคริปต์เป็นผู้บังคับ โดยนับบรรทัด START ใน `.ai/<RUN>/runs.log` ไม่ใช่ให้โมเดลนับเอง), หยุดทันทีเมื่อพบปัญหาเดิมซ้ำสองรอบ แก้ได้ที่บล็อก Configuration ต้นไฟล์ SKILL.md
- **แต่ละรัน มีโฟลเดอร์ของตัวเอง** `.ai/<YYYYMMDD-HHMM>/` เก็บ plan, brief, result, review, status ทำให้ resume ได้และไม่ชนกันระหว่างรัน

## 3. สิ่งที่ยืนยันแล้ว และยืนยันอย่างไร

จากการติดตั้ง `@openai/codex` (codex-cli 0.160.1) ในเครื่องทดสอบและรัน `--help`:

- `codex exec` รับ `--cd/-C`, `--sandbox/-s` (read-only, workspace-write, danger-full-access), `--model/-m`, `--config/-c`, `--output-last-message/-o`, `--skip-git-repo-check`, `--ephemeral`, `--json`, `--output-schema` และอ่าน prompt จาก stdin เมื่อใช้ `-`
- คำสั่งรูปแบบเดียวกับที่ skill ใช้ (`--cd . --sandbox workspace-write --model ... --config 'model_reasoning_effort="high"' --output-last-message ... -`) ผ่านการ parse และ banner แสดง `sandbox: workspace-write`, `approval: never`, `reasoning effort: high`
- `codex exec resume` มี `--last` และ `--all` ("disables cwd filtering" แสดงว่า `--last` กรองตามโฟลเดอร์ปัจจุบันเป็นค่าเริ่มต้น) แต่ไม่มี `--sandbox`, `--cd`
- ชื่อโมเดลที่ไม่มีจริงผ่านการ parse ได้ จะไปล้มตอนเรียก API เท่านั้น

จากเอกสาร Claude Code (code.claude.com):

- skill ระดับผู้ใช้ที่ `~/.claude/skills/<name>/SKILL.md` ใช้ได้ทุกโปรเจกต์บนเครื่องนั้น แต่ไม่ใช่ใน Cowork หรือ cloud session ระดับผู้ใช้มีลำดับเหนือระดับโปรเจกต์เมื่อชื่อซ้ำ
- `disable-model-invocation: true` ทำให้ Claude เรียกเองไม่ได้ และ `$ARGUMENTS` รับข้อความหลัง `/delegate` (ทั้งสองอย่างนี้ **ไม่ได้ใช้ใน SKILL.md แล้ว** ดูหัวข้อ 8) ถ้าไม่มี placeholder Claude Code จะต่อข้อความไว้ท้ายไฟล์เป็นบรรทัด `ARGUMENTS: ...`
- กฎ permission จับคู่ทีละคำสั่งย่อยที่ต่อด้วย `&&`/`||`/`;`, deny ชนะ allow, `permissions.allow` รวมข้ามระดับ, `env` ใน settings.json ใช้ตั้ง `BASH_MAX_TIMEOUT_MS` ได้ (ค่าเริ่มต้นเพดาน 10 นาที)
- Claude Code อ่าน AGENTS.md เองเฉพาะเมื่อไม่มี CLAUDE.md ถ้ามี CLAUDE.md ต้องใส่ `@AGENTS.md`

จากการจำลองใน repo ชั่วคราวด้วย codex ตัวแทน (ไม่ใช่ Codex จริง):

- `.ai/.gitignore` ที่มี `*` ทำให้ `git status` ว่าง ทั้งใน repo ปกติและ worktree
- `git add -N .` ทำให้ไฟล์ใหม่ที่ Codex สร้างโผล่ใน `git diff --name-only` การตรวจ scope จับไฟล์นอกขอบเขตได้
- รูปแบบ redirect (`- < brief > stdout 2> log` พร้อม `--output-last-message`) ทำงานถูกต้อง
- `git add -A` + `git commit` ไม่รวม `.ai/`
- `install.sh` ผ่าน 4 สถานการณ์: ติดตั้งใหม่, ไฟล์ตรงกัน, ไฟล์ต่าง (ปฏิเสธ exit 2), `--force` (สำรองไฟล์เดิม)

## 4. สิ่งที่ยังไม่ได้ยืนยัน หรือยังค้าง

1. **(อัปเดต)** ผู้ใช้รันบน Mac จริงแล้วสำเร็จกับ v3 (เส้นทางปกติ, โจทย์ขัดแย้ง, แก้ไฟล์ test ที่อนุญาต) ดูหัวข้อ 11 ส่วน v4 ยังไม่เคยรันบน Mac ให้เริ่มจาก `bash tests/run_tests.sh`
2. **ชื่อโมเดลที่ใช้ได้กับบัญชีของคุณ** บล็อก Configuration ตั้ง `CODEX_MODEL` ว่างไว้ (ใช้ default ของ Codex) เอกสารระบุ `gpt-6.1-sol` เป็นตัวอย่างเท่านั้น ไม่ใช่รายการยืนยัน ให้ตรวจจาก Codex เองบนเครื่อง แล้วค่อยล็อกค่า
3. **ข้อความของ `codex login status` เมื่อล็อกอินแล้ว** skill สมมติว่ามีคำว่า `Logged in` (ทดสอบได้เฉพาะกรณี `Not logged in`) ถ้าข้อความจริงต่างออกไป ให้ปรับ preflight ข้อ 3
4. **`CODEX_EFFORT=high`** Codex parse ได้ แต่ยังไม่ยืนยันว่าโมเดลที่เลือกรับค่านี้
5. **การทำงานของ SKILL.md ใน Claude Code จริง** ยังไม่ได้ทดสอบว่า `/delegate` ปรากฏในเมนู, ข้อความงานที่พิมพ์หลัง `/delegate` ไปถึง Claude (ตามเอกสารจะถูกต่อท้ายไฟล์เป็นบรรทัด `ARGUMENTS:`) และ Claude ทำตามขั้นตอนครบ
6. **Permission prompt** การเขียนไฟล์ใน `.ai/` ครอบด้วย `Edit(.ai/**)` แล้ว แต่คำสั่งทดสอบ/lint ของแต่ละโปรเจกต์ต้องเพิ่มใน `.claude/settings.local.json` ของ repo นั้น หรือใช้โหมด acceptEdits มิฉะนั้นวงจรจะหยุดรอการอนุมัติ
7. **เพดานเวลา** ค่า `CODEX_TIMEOUT_SEC=540` (Bash timeout = ค่านี้ + 60 วินาที = 600000 ms) ใช้ได้กับ settings เริ่มต้น หากต้องการนานกว่านี้ให้ merge บล็อก `env` ใน snippet แล้วค่อยเพิ่มค่าใน SKILL.md
8. **ตัวเลือกที่ยังไม่ได้ผนวก:** `codex exec review` (มีใน 0.160.1) ใช้เป็นความเห็นที่สองได้, `--ephemeral` ถ้าไม่ต้องการให้ Codex เก็บ session ไฟล์
9. **ข้อจำกัดของ skill ระดับผู้ใช้:** ใช้ไม่ได้ใน Cowork หรือ cloud session ต้องรัน `claude` บน Mac โดยตรง
10. ใน sandbox ทดสอบ `./install.sh` รันตรงไม่ได้ (mount ไม่ให้ execute) ใช้ `bash install.sh` แทน บน Mac ปกติไม่น่ามีปัญหานี้

## 5. แผนทดสอบบน Mac (ทำตามลำดับ หยุดทันทีถ้าข้อใดไม่ผ่าน)

1. ติดตั้ง Codex CLI และล็อกอินเอง (`codex login`) แล้วตรวจ `codex login status` จดข้อความที่ได้ไว้ (ข้อ 4.3)
2. `bash install.sh` แล้วรัน `node merge-settings.js --dry-run` เพื่อดูตัวอย่าง จากนั้นรัน `node merge-settings.js` จริง และรัน `bash tests/run_tests.sh` (v4) ต้องได้ `RESULT: 61 passed, 0 failed` (v4.4)
3. สร้าง repo ทดสอบเล็ก ๆ: ไฟล์ `src/app.py` ที่มีฟังก์ชัน `add` คืนค่าผิด และ `tests/test_app.py` ที่ fail commit ไว้ แล้วคัดลอก `repo-templates/AGENTS.md` ไปปรับคำสั่งทดสอบ
4. `cd` เข้า repo, เปิด `claude`, พิมพ์ `/delegate แก้ฟังก์ชัน add ให้ผ่าน tests/test_app.py` (ใช้ข้อมูลตัวอย่างเท่านั้น)
5. สิ่งที่ต้องเห็น: ถามยืนยันส่งข้อมูลหนึ่งครั้ง, สร้าง branch `ai/delegate-<RUN>`, สร้าง `.ai/<RUN>/` พร้อม plan และ task-01-r1.md, เรียก Codex ผ่าน `delegate-run.sh` (v4.1 ขึ้นไป: เห็นบรรทัด `runs_total=` และ `settings confirmed approval=never sandbox=workspace-write` และมี `.ai/<RUN>/runs.log`), review ไฟล์ขึ้นต้นด้วย `verdict: PASS`, มีคำสั่งที่รันและ exit code, `delegate-run.sh check-status <RUN>` ได้ exit 0, commit บน branch, ไม่มี push, `git status` สะอาด
6. ทดสอบ FAIL path: ให้ task ที่ทำให้ Codex แก้ไฟล์นอกขอบเขตได้ง่าย แล้วดูว่า Claude จับได้และเขียน brief รอบที่ 2
7. ทดสอบ `/delegate resume` หลังปิด `claude` กลางงาน
8. หลังทุกข้อผ่าน ค่อยใช้กับ repo จริง และเติม AGENTS.md ของ repo นั้น

## 6. ความแก้ไขจากคำแนะนำก่อนหน้าในแชต

- เดิมแนะนำเพิ่ม `.ai/` ใน `.git/info/exclude` ตอนนี้ใช้ `.ai/.gitignore` แทน
- เดิมแนะนำ `codex exec resume --last` ตอนนี้ไม่ใช้
- เพิ่มสิ่งที่ไม่ได้กล่าวไว้เดิม: ขั้นตอนยืนยันส่งข้อมูล, ตรวจล็อกอินจากข้อความ, เพดานจำนวนการเรียก Codex, ข้อควรระวังเรื่อง macOS ไม่มีคำสั่ง `timeout`

## 7. ข้อกำหนดสำหรับผู้ที่แก้ไฟล์ชุดนี้ต่อ

- ห้ามผ่อนกฎความปลอดภัยใน SKILL.md: ไม่ใช้ `--yolo`, `--dangerously-bypass-approvals-and-sandbox`, `danger-full-access`; ไม่ push/merge/deploy; ไม่ประกาศ PASS จากรายงานของ Codex อย่างเดียว
- ก่อนเปลี่ยนค่า default ในบล็อก Configuration ให้ถามผู้ใช้
- ถ้าแก้ `delegate-run.sh` ให้รัน `bash tests/run_tests.sh` ต้องผ่านทุกข้อ (ชุดทดสอบนี้ผ่านการทดสอบกลับด้านแล้ว: จงใจทำสคริปต์ให้เสีย 4 แบบ คือไม่ใช้ KILL, ปิดการตรวจเพดาน, ไม่ปล่อย lock, ปิดการตรวจ codex_runs ชุดทดสอบจับได้ทั้งหมด แบบแรกจับได้ด้วยการค้างไม่จบเพราะ Codex ปลอมไม่ยอมตาย)
- ถ้าแก้ SKILL.md ให้รัน `bash -n install.sh` และตรวจ JSON ของ snippet อีกครั้ง และตรวจ SKILL.md ด้วย `python3 -I /mnt/skills/examples/skill-creator/scripts/quick_validate.py <โฟลเดอร์ของ skill>` (โฟลเดอร์ที่มี SKILL.md อยู่) ต้องได้ "Skill is valid!"
- frontmatter ต้องมีเฉพาะ `name`, `description`, `compatibility`, `metadata` (คีย์อื่นถูกปฏิเสธตอนอัปโหลด) และ description ต้องไม่มีเครื่องหมาย `<` หรือ `>` ส่วนเนื้อหาด้านล่างใช้ได้ตามปกติ
- ไม่ใส่ `$` ในเนื้อหา SKILL.md โดยไม่จำเป็น เพราะตัวแปรที่ขึ้นต้นด้วย `$` อาจถูก Claude Code แทนค่า
- ผู้ใช้มีปัญหา skill หลายเวอร์ชันไม่ตรงกันระหว่างเครื่อง จึงให้มี SKILL.md ตัวจริงชุดเดียว และใช้ `install.sh` (ปฏิเสธการเขียนทับถ้าต่างกัน) แทนการคัดลอกด้วยมือ

## 8. แก้ error ตอนบันทึก skill ("description cannot contain XML tags")

- **สาเหตุที่ 1:** description เดิมมี `<task>` ซึ่งตัวตรวจสอบมองเป็น XML tag แก้โดยเขียน description ใหม่ไม่ให้มีเครื่องหมาย `<` หรือ `>`
- **สาเหตุที่ 2 (จะ error ตามมาถ้าแก้เฉพาะข้อ 1):** frontmatter มีคีย์ `disable-model-invocation` ตัวตรวจสอบทางการ (`quick_validate.py`) อนุญาตเฉพาะ `name`, `description`, `license`, `allowed-tools`, `metadata`, `compatibility` จึงลบคีย์นี้ออกและเอา `$ARGUMENTS` ออกด้วย (Claude Code จะต่อข้อความงานไว้ท้ายไฟล์เป็นบรรทัด `ARGUMENTS:` เอง)
- **ผลที่ตามมา:** Claude อาจเรียก skill นี้เองได้ จึงใส่การป้องกันสองชั้นไว้แล้ว คือ description ระบุ "Use only when the user explicitly types /delegate ... Never start it on your own" และต้นเนื้อหาสั่งให้หยุดถ้าไม่ได้ถูกเรียกอย่างชัดแจ้ง
- **ถ้าต้องการล็อกแน่นอนใน Claude Code บน Mac:** เพิ่มบรรทัด `disable-model-invocation: true` ในสำเนาที่ `~/.claude/skills/delegate/SKILL.md` ด้วยตัวเอง (ห้ามใส่ในไฟล์ที่จะอัปโหลด) และจำไว้ว่า `install.sh --force` จะเขียนทับสำเนานั้น (มีไฟล์สำรองให้)
- **ถ้าบันทึกเป็น skill ในบัญชี (claude.ai หรือ Cowork):** บันทึกได้แล้ว แต่ใน cloud session ไม่มี Codex จึงจะหยุดที่ preflight ใช้งานจริงต้องรันใน Claude Code บน Mac ควรเลือกใช้ไฟล์ในเครื่องเป็นฉบับหลักแบบเดียว เพื่อเลี่ยงปัญหาหลายเวอร์ชันไม่ตรงกัน
- ตรวจแล้วด้วย `quick_validate.py`: "Skill is valid!" (description 231 ตัวอักษร ไม่มี `<` `>`; frontmatter มีเฉพาะ `name`, `description`, `compatibility`)

## 9. สิ่งที่เพิ่มหลังทดสอบ repo ตัวอย่าง

- **Baseline run ใน preflight:** รันคำสั่งทดสอบหนึ่งครั้งบน working tree ที่สะอาดแล้วตรวจ `git status --porcelain` ถ้ามีไฟล์ untracked เกิดขึ้น (เช่น `__pycache__/`) ให้หยุดและขอให้ผู้ใช้เพิ่ม `.gitignore` เองก่อน เหตุผล: ทดสอบพบว่า `python3 -m unittest` สร้าง `__pycache__/` ซึ่งจะถูกนับเป็นไฟล์นอกขอบเขตและอาจถูก commit
- **`merge-settings.js`** เพิ่มเพื่อไม่ให้ต้องแก้ JSON ด้วยมือ ทดสอบแล้ว 3 กรณี: ยังไม่มีไฟล์, มีไฟล์เดิมพร้อมคีย์อื่นและค่า env ต่าง (คงค่าเดิมไว้), และ JSON เสีย (ไม่เปลี่ยนอะไร)

## 10. v4: สิ่งที่เปลี่ยน และเหตุผล

**ปัญหาที่พบจากการทดสอบจริงบน Mac (รัน repo `delegate-trap`):** `status.md` ค้างค่าเก่าหลังงานจบ (`state: DONE` แต่ `codex_runs: 0`, `last_verdict: none`, `next_step: run Codex...`) ทั้งที่ Codex ถูกเรียกจริงหนึ่งครั้ง และผล PASS ถูกต้อง สาเหตุ: Claude ไม่ทำตามคำสั่ง "อัปเดต status หลังทุกขั้น" ซึ่งเป็นงานทะเบียนที่พึ่งความจำของโมเดล และเพดาน 12 ครั้งที่ให้โมเดลนับเองก็พึ่งสิ่งเดียวกัน จึงย้ายงานเหล่านี้ไปให้โค้ดทำ

**สิ่งที่ v4 ทำ:**

- `delegate-run.sh codex <RUN> <K> <R> ...` เป็นทางเดียวที่ใช้เรียก Codex สคริปต์เขียน `runs.log` (START/END) เอง ปฏิเสธการเริ่มเมื่อถึงเพดาน (exit 3) ใช้ lock กันรันซ้อน (exit 4) ล้าง lock ที่ค้างจากโปรเซสที่ตายแล้ว เมื่อถูก TERM/INT จะหยุด Codex และ process ลูกทั้งต้นไม้ แล้วบันทึก `rc=interrupted` ปฏิเสธการเขียนทับ result เดิม (exit 2) หยุด Codex เองเมื่อเกินเวลา (exit 8, บันทึก `rc=timeout`)
- `delegate-run.sh count <RUN>` พิมพ์จำนวนการเรียก Codex จริงจาก ledger
- `delegate-run.sh check-status <RUN>` เทียบ `status.md` กับของจริง: `codex_runs` ต้องเท่ากับ ledger, `last_verdict` ต้องตรงกับบรรทัดแรก `verdict: ...` ของ review ล่าสุด (review ทุกไฟล์ต้องขึ้นต้นด้วยบรรทัดนี้), ถ้า `state: DONE` ต้องมี review ล่าสุดเป็น PASS, มี `summary.md`, และ `next_step` ขึ้นต้นด้วย `none` ผิดแล้ว exit 7 SKILL.md สั่งให้รันก่อนขอแผน, ก่อนรายงาน BLOCKED และก่อนรายงาน DONE
- `delegate-run.sh version` ใช้ใน preflight เพื่อจับกรณี SKILL.md กับสคริปต์คนละรุ่น (v4.4 พิมพ์ `delegate-run 4.4`) (ปัญหา zip ชื่อซ้ำที่เคยเกิด)
- `status.md` แยกฟิลด์เป็นบรรทัดละหนึ่งค่า (`slice:`, `round:`, `codex_runs:`) เพื่อให้ตรวจด้วยโค้ดได้
- `settings.snippet.json`: เลิก allow `codex exec *` (เหลือ `codex exec --help`) เพิ่ม allow `bash ~/.claude/skills/delegate/delegate-run.sh *` (merge-settings.js เพิ่มรูปแบบ path เต็มด้วย) และ deny `Edit(.ai/*/runs.log)` (ชั้นป้องกันเพิ่ม ยังไม่ได้ทดสอบกับ Claude Code จริง) ผู้ที่ merge v3 ไปแล้วจะยังมี `Bash(codex exec *)` ค้างใน settings เพราะสคริปต์ merge ไม่ลบรายการ ลบเองได้ถ้าต้องการให้ทุกการเรียก Codex ตรง ๆ ถูกถามสิทธิ์
- brief template เพิ่มบรรทัด "brief และ AGENTS.md มีลำดับเหนือ skill/คำสั่งส่วนตัวที่ Codex โหลดมา"

**ทดสอบแล้ว (ในเครื่องทดสอบ Linux):** `tests/run_tests.sh` 57 ข้อผ่านทั้งหมด (v4 เดิม 50 ข้อ ผ่านบน Mac จริงแล้วด้วย bash 3.2.57) ครอบคลุม: รันปกติ, flag ที่ส่งให้ codex, ledger, lock (เป็นอยู่/ค้าง), เพดาน (ไม่เรียก codex เมื่อถึงเพดาน), codex ล้มเหลว/ไม่มีผลลัพธ์, ตรวจ argument, TERM ฆ่า process ลูกและหลาน, timeout ของสคริปต์ (รวมกรณี Codex ไม่ยอมตายด้วย TERM ต้อง KILL), และ check-status กับสถานการณ์ stale แบบจริง นอกจากนี้ทดสอบกับ `codex` ตัวจริงที่ยังไม่ล็อกอินแล้ว: ส่ง TERM ระหว่างรัน process ของ node และ codex ถูกปิดครบ, ledger บันทึก interrupted, lock ถูกปล่อย, banner แสดง `workspace-write` และ effort ตามที่ส่ง ทดสอบ install.sh (ใหม่/ซ้ำ/ปฏิเสธ/force) และ merge-settings.js กับ settings ที่มีรายการ v3 อยู่แล้ว

**ยังไม่ได้ทดสอบ (ต้องทำบน Mac):**

1. `bash tests/run_tests.sh` บน macOS (bash 3.2, `ps`/`pgrep` แบบ BSD) ผลทดสอบทั้งหมดข้างต้นมาจาก Linux
2. การรันจริงใน Claude Code ว่าโมเดลทำตามขั้นตอน 2.3/2.4 และเรียก `check-status` ก่อนจบจริง (สคริปต์รับประกันได้เฉพาะเมื่อถูกเรียก การบังคับให้เรียกยังเป็นคำสั่งใน SKILL.md)
3. กฎ deny `Edit(.ai/*/runs.log)` และ allow รูปแบบ `~` ว่า Claude Code จับคู่ได้ตามคาด
4. เส้นทางที่ยังไม่เคยทดสอบจริง: รอบ FAIL แล้วแก้ในรอบที่ 2, ตรวจ "ไม่มีความคืบหน้า", หลายชุดงาน (multi-slice), `/delegate resume`, ขั้นรอยืนยันแผน, เส้นทาง BLOCKED จาก timeout

## 11. ข้อสังเกตจากการทดสอบ v3 บน Mac ของผู้ใช้

- เส้นทางปกติผ่าน: user-level `/delegate` ทำงาน, Codex เขียนโค้ด (ยืนยันจากไฟล์ result, log และจำนวน token 9,808), review PASS, commit บน branch `ai/delegate-*`, ไม่มี push, `git status` สะอาด
- repo `delegate-trap`: Claude หยุดก่อนเรียก Codex เมื่อโจทย์ขัดแย้งกันเอง (ประตูตรวจโจทย์ทำงาน) แล้วเมื่อเลือกทางเลือกที่แนะนำ ก็แก้ไฟล์ test ที่ได้รับอนุญาตและผ่าน
- โมเดลที่ Codex ใช้จริงบนเครื่องผู้ใช้คือ `gpt-6.1-sol` (default ของ Codex) ตั้ง `CODEX_MODEL` ล็อกได้ถ้าต้องการ
- **Codex อ่าน `ponytail/SKILL.md` ซึ่งเป็น skill ส่วนตัว** (ปรากฏในรายงานผล) ตรวจที่มาได้ด้วย `find ~/.codex ~/.agents -ipath "*ponytail*"` v4 เพิ่มบรรทัดใน brief ให้ brief และ AGENTS.md มีลำดับเหนือกว่า แต่ยังไม่ได้ทดสอบว่าได้ผลหรือไม่
- **อธิบายได้แล้ว: `approval: on-request` มาจาก `approvals_reviewer = "auto_review"` ใน `~/.codex/config.toml` ของผู้ใช้ (บรรทัด 7)** จำลอง config เดียวกันในเครื่องทดสอบแล้วได้ผลเหมือนกัน: ไม่มี config หรือมี `approvals_reviewer="user"` banner แสดง `approval: never`, มี `auto_review` แสดง `on-request`, และ `--config 'approval_policy="never"'` ทับให้กลับเป็น `never` ได้ ตามเอกสาร OpenAI (https://learn.chatgpt.com/docs/sandboxing/auto-review.md) auto-review ส่งคำขอที่เกิน sandbox (คำสั่งที่ขอสิทธิ์สูงขึ้น, เครือข่ายที่ sandbox ปิด, แก้ไฟล์นอก writable roots, การเรียก MCP/app tool ที่ต้องอนุมัติ) ให้ reviewer อัตโนมัติตัดสินแทนคน และทำงานเมื่อ `approval_policy` เป็น `on-request` เท่านั้น ส่วนกรณี `never` "ไม่มีอะไรให้ review" เอกสารไม่ได้ระบุว่าครอบคลุม `codex exec` หรือไม่ จึงไม่ถือว่าปลอดภัยโดยปริยาย ผลคือ v3 และ v4 รันบนเครื่องผู้ใช้ด้วยสภาพที่ sandbox อาจไม่ใช่เส้นแบ่งเด็ดขาด (ไม่มีหลักฐานว่าเกิดขึ้นจริงในการทดสอบ: งานที่ทดสอบแก้เฉพาะไฟล์ในโฟลเดอร์งาน)
- **v4.1 แก้โดย:** สคริปต์ส่ง `--config 'approval_policy="never"'` ทุกครั้ง (เกิน sandbox แล้วถูกปฏิเสธ ไม่มีใครอนุมัติแทน) และหลัง Codex จบจะอ่านบรรทัด `approval:` กับ `sandbox:` ที่ banner ใน log ถ้าไม่ใช่ `never` และ `workspace-write` จะ exit 9 (BLOCKED, ไม่รับผลงาน) ถ้าไม่พบ banner จะแจ้งหมายเหตุแต่ไม่ล้มรัน (exit 9 มาก่อน exit 6 แต่หลัง exit 5, 8)
- **ponytail คือ plugin ของ Codex** (marketplace `ponytail` เวอร์ชัน 4.13.0 พร้อม `.ponytail-active` และ `ponytail-mcp` อยู่ใต้ `~/.codex/plugins/`) ถูกโหลดเข้าทุกเซสชัน Codex รวมถึงรอบของ /delegate ผู้เขียนชุดนี้ไม่ทราบว่า plugin ทำอะไรและเครื่องมือ MCP ของมันถูกจำกัดโดย sandbox หรือไม่ (ยังไม่ได้ยืนยัน) ผู้ใช้ตัดสินใจเองว่าจะปิดระหว่างงาน /delegate หรือไม่
- ใช้ token ประมาณ 9.8 พันต่อการรัน Codex หนึ่งครั้งสำหรับงานเล็ก

## 12. ผลทดสอบ v4 บน Mac ของผู้ใช้ (ผ่านโดย Claude Code ของผู้ใช้เอง) และที่มาของ v4.1

- bash 3.2.57 (arm64-apple-darwin25), Codex 0.160.1, `codex login status` = `Logged in using ChatGPT`
- `tests/run_tests.sh` (v4): 50 passed, 0 failed บน macOS ไม่มี process ค้าง
- install.sh --force ผ่าน (สำรอง SKILL.md รุ่นเก่า), `delegate-run 4`, cmp ไฟล์ติดตั้งตรงกับในชุด
- `merge-settings.js` ถูก permission ของ Claude Code ปฏิเสธเพราะแก้ `~/.claude/settings.json` (Self-Modification) ผู้ใช้รันเองจาก terminal สำเร็จ ตรวจแล้วมีรายการ delegate-run.sh (รูป `~` และ path เต็ม) และ deny `Edit(.ai/*/runs.log)` JSON ยัง parse ได้ มีไฟล์สำรอง
- ทดสอบกับ Codex จริงใน repo ชั่วคราวหนึ่งครั้ง: exit 0, `runs_total=1/1`, ใช้เวลา 13 วินาที, `hello.txt` = ok, ledger START/END `rc=0`, `--max-runs 1` รอบสอง exit 3 โดยไม่เรียก Codex, `check-status` แบบ stale exit 7 พร้อม MISMATCH 3 บรรทัด และหลังแก้ exit 0
- banner บนเครื่องผู้ใช้: `approval: on-request` (สาเหตุ ดูหัวข้อ 11) นำไปสู่ v4.1
- ผู้ใช้ที่ติดตั้ง v4 แล้วให้รัน `bash install.sh --force` จากโฟลเดอร์ v4.1 (settings ไม่ต้อง merge ซ้ำ รายการเหมือนเดิม)

## 13. ผลทดสอบ v4.1 บน Mac และที่มาของ v4.2

- ชุดทดสอบ v4.1: 57 passed, 0 failed บน macOS (bash 3.2.57) ติดตั้ง v4.1 ผ่าน
- ทดสอบสคริปต์กับ Codex จริงใน repo ชั่วคราว: exit 0 ใน 14 วินาที, บรรทัด `settings confirmed approval=never sandbox=workspace-write`, banner ใน log แสดง `approval: never` ทั้งที่ `config.toml` ของผู้ใช้ยังมี `approvals_reviewer = "auto_review"` (ยืนยันว่า `--config approval_policy="never"` ทับได้จริงบนเครื่องผู้ใช้)
- ทดสอบ `/delegate` เต็มวงจรใน Claude Code จริง (repo `delegate-test`, โจทย์ "เพิ่ม multiply(a, b) พร้อมเทสต์"): Claude รัน baseline, เขียน status.md แยกฟิลด์ตามแม่แบบ (มีบรรทัด `baseline:`), เรียก Codex ผ่าน `delegate-run.sh` หนึ่งครั้ง (START/END `rc=0` ใน `runs.log`), review PASS, commit บนสาขาเดิม, `git status --porcelain` ว่าง และ `check-status` ได้ exit 0 (`codex_runs=1, ledger=1, newest review=PASS`) นี่คือการยืนยันว่าอาการ status.md ค้างของ v3 ไม่เกิดซ้ำในกรณีนี้
- **ข้อบกพร่องที่พบจากผลนั้นและแก้ใน v4.2:** สาขาเริ่มต้นขึ้นต้นด้วย `ai/` (`ai/delegate-20261007-1543` จากรันก่อนหน้า) ตามกติกา "อยู่บนสาขา ai/ เดิม" จึงได้ `original_branch` เท่ากับ `task_branch` คำแนะนำตอนจบเดิม ("ดูผลด้วย `git log ORIGINAL_BRANCH..HEAD` และลบ task branch เพื่อยกเลิก") จะผิดในกรณีนี้ (ช่วง log ว่าง และการลบสาขาจะลบงานของรันก่อนหน้าด้วย) v4.2 ให้ใช้ `INITIAL_BASE` เป็นจุดอ้างอิงในการดูผล และแยกวิธียกเลิกตามว่า task_branch เท่ากับ original_branch หรือไม่ (ถ้าเท่ากัน ห้ามลบสาขา ให้ผู้ใช้ตัดสินใจเรื่อง `git reset --hard <INITIAL_BASE>` เอง) แก้เฉพาะข้อความใน SKILL.md ไม่กระทบสคริปต์ (เลขเวอร์ชันสคริปต์ปรับเป็น 4.2 เพื่อให้ preflight จับกรณีไฟล์สองตัวคนละรุ่นได้) ยังไม่ได้ยืนยันว่า Claude รายงานข้อความนี้ถูกต้องในการรันจริง
- **ยังไม่ได้ทดสอบ:** รอบ FAIL แล้วแก้รอบที่ 2, ตรวจ "ไม่มีความคืบหน้า", หลายชุดงานพร้อมประตูยืนยันแผน (เกิน 4 ชุดงาน), `/delegate resume` หลังถูกขัดจังหวะ, exit 9 กับ Codex ตัวจริง, ผลของ plugin `ponytail` ต่อรอบ /delegate

## 14. ผลทดสอบ v4.2 และที่มาของ v4.3

- ติดตั้ง v4.2 บน Mac ผ่าน (ชุดทดสอบ 57/57, `delegate-run 4.2`, ข้อความใหม่ของ SKILL.md ปรากฏ, settings เดิมยังใช้ได้โดยไม่ต้อง merge ซ้ำ)
- ทดสอบ 5 ชุดงาน (`stats.py`, run 20261008-1003): Claude หยุดรออนุมัติแผนเพราะเกิน 4 ชุดงาน (ยืนยันจาก transcript), Codex 5 ครั้ง `rc=0` ครั้งละ 32-42 วินาที, review ทั้ง 5 ไฟล์ขึ้นต้น `verdict: PASS`, diff แตะเฉพาะ `stats.py` กับ `test_stats.py`, unittest 41 ตัวผ่าน, `check-status` exit 0, ข้อความท้ายงานแนะนำดูผลด้วย `INITIAL_BASE`
- ทดสอบขัดจังหวะ (กด Esc ขณะ Codex ทำงานได้ 2 วินาที, โจทย์ `range_of`): ledger บันทึก `rc=interrupted` ไม่มีผลลัพธ์และไม่มีไฟล์เปลี่ยน; Claude พบ status.md ค้าง (จำนวนรันไม่ตรง ledger) แก้ให้ตรงตามกติกา resume ข้อ 2, รัน brief เดิมซ้ำ (นับเป็นการเรียก Codex ครั้งที่ 2) ได้ผล PASS และ commit 89b51bc รายงานข้อสมมติเรื่อง ValueError กับข้อมูลว่างอย่างโปร่งใส ผู้ใช้รายงานว่า unittest 50 ตัวผ่าน
- **ช่องว่างที่พบและแก้ใน v4.3 (ข้อความใน SKILL.md ส่วน Resume mode เท่านั้น):** กฎเดิมให้หยุดถามเฉพาะกรณี working tree ไม่ตรงหรือ ledger จบด้วย START ที่ไม่มี END จึงไม่ครอบคลุมกรณีที่ END เป็น `rc=timeout` หรือ rc ไม่เป็นศูนย์ หรือ state เป็น BLOCKED ซึ่งอาจทำให้ resume สั่ง Codex รัน brief เดิมซ้ำโดยอัตโนมัติจนหมดเวลาอีกครั้ง (เสียเงินโดยไม่ได้อะไร) v4.3 ให้หยุดถามในกรณีเหล่านี้ และบันทึกกฎของกรณี `rc=interrupted` ที่ working tree สะอาดและไม่มี result ไว้ชัดเจนว่าให้รันรอบเดิมซ้ำพร้อมแจ้งจำนวนรันที่ใช้ไป (พฤติกรรมที่เห็นจริงในการทดสอบ)
- **ยังไม่ได้ทดสอบ:** ผลจากการทดสอบข้างบนไม่ยืนยันว่าเป็น `/delegate resume` ในเซสชันใหม่หรือเป็นการพิมพ์ต่อในเซสชันเดิม; การตรวจว่าไม่มี process Codex ค้างหลังกด Esc และ `.lock` ถูกปล่อย; รอบ FAIL แล้วแก้รอบที่ 2; การหยุดเมื่อไม่มีความคืบหน้า; exit 9 กับ Codex จริง; กฎ resume ใหม่ของ v4.3 (rc=timeout / BLOCKED)

## 15. ผลตรวจหลังขัดจังหวะ และที่มาของ v4.4

- ผลบน Mac หลังกด Esc ระหว่าง Codex ทำงาน (run 20261008-1037): `runs.log` มี START/END `rc=interrupted` (2 วินาที) ตามด้วย START/END `rc=0` (42 วินาที), ไม่มี `.lock`, `check-status` exit 0 (`codex_runs=2, ledger=2`) ไม่พบ process ของรัน /delegate ค้าง (ผล `ps` ที่ผู้ใช้ส่งมาทุกบรรทัดมี PID ต่ำกว่า 37951 ซึ่งเป็น PID ของสคริปต์รอบที่ถูกขัดจังหวะ จึงเกิดก่อนรันนั้นทั้งหมด และไม่มีบรรทัดใดมี `delegate-run` หรือ `exec --cd`)
- ผู้ใช้ยืนยันว่ารอบที่สองเป็นการพิมพ์ให้ต่อ **ในเซสชันเดิม** ไม่ใช่ `/delegate resume` ในเซสชันใหม่ ดังนั้นกฎ Resume mode (รวมกฎใหม่ของ v4.3) **ยังไม่เคยถูกทดสอบจริง**
- **ข้อบกพร่องที่พบจากผล `ps` ของผู้ใช้ (แก้ใน v4.4):** เครื่องผู้ใช้มี ChatGPT desktop app รัน process ชื่อ `codex exec-server --remote ...` และ `codex app-server` (daemon 0.161.0) คำสั่ง `pgrep -fl "codex exec"` เดิมใน SKILL.md (ข้อ 2.4 และ Resume ข้อ 3) จะจับ `exec-server` นั้นเป็น "Codex ของเรายังรันอยู่" ทำให้ Claude หยุดโดยไม่จำเป็นหรืออาจเข้าใจผิด ยืนยันด้วยการจำลองแล้ว v4.4 ใช้ `pgrep -fl "[e]xec --cd \. --sandbox workspace-write"` ซึ่งตรงกับคำสั่งที่ `delegate-run.sh` สร้างเท่านั้น (วงเล็บ `[e]` ป้องกันคำสั่งจับตัวเอง) และเพิ่มข้อความใน SKILL.md ให้ละเว้น process Codex อื่นของเครื่อง ห้าม kill เพิ่มเทสต์ T14 ที่ดึง pattern จาก SKILL.md มาทดสอบกับ process จำลองสองแบบ (ผ่านการทดสอบกลับด้านแล้ว: ถ้าใส่ pattern เก่ากลับ T14 ล้ม)
- ข้อสังเกต: ผลทดสอบ `ps` ที่ผมให้ผู้ใช้รันใช้ `grep -E "codex|delegate-run"` กว้างเกินไป จึงจับ process ของ desktop app ทั้งหมด ควรใช้ `grep -E "exec --cd \. --sandbox|delegate-run"`
- **ยังไม่ได้ทดสอบ:** `/delegate resume` ในเซสชันใหม่ (กฎข้อ 3-4 ของ v4.3), รอบ FAIL แล้วแก้รอบที่ 2, การหยุดเมื่อไม่มีความคืบหน้า, exit 9 กับ Codex จริง, pattern ใหม่ของ pgrep กับ process จริงบน macOS (ทดสอบแล้วบน Linux)

## 16. ผลทดสอบ `/delegate resume` ในเซสชันใหม่ (repo `delegate-test-resume`, v4.4)

ที่มาของข้อมูล (ตรวจเมื่อ 2026-10-09): ไฟล์ใน `delegate-test-resume/.ai/`, `git log` ของ repo นั้น และ transcript ของ Claude Code ทั้ง 4 เซสชันใน `~/.claude/projects/-Users-seal-Documents-GitHub-delegate-test-resume/` สคริปต์ที่ติดตั้งตรงกับ kit v4.4 (`cmp` ตรงกัน, ติดตั้งเมื่อ 2026-10-08 11:13:37, `delegate-run 4.4`) Claude ที่เป็นผู้วางแผนและตรวจรับในทุกเซสชันคือ `claude-sonnet-5-5`

repo ทดสอบ: `mathx.py` + `test_mathx.py` (unittest), สาขาเริ่มต้น `master`, มี `.gitignore` แล้ว

| เซสชัน | เริ่ม (+07) | คำสั่ง | ผล |
|---|---|---|---|
| `56d92ad9` | 11:19:58 | `/delegate` เพิ่ม `sub` และ `mul` แยก 2 slice (run `20261008-1120`) | กด Esc ระหว่าง Codex slice 01 ทำงานได้ 4 วินาที ledger บันทึก `rc=interrupted` แล้วปิดเซสชัน |
| `a6a0c446` | 11:21:55 | `/delegate resume` (เซสชันใหม่) | รัน slice 01 รอบเดิมซ้ำ PASS, slice 02 PASS, DONE |
| `7e3568dd` | 11:26:29 | `/delegate` เพิ่ม `div` (run `20261008-1126`) โดยผู้ใช้แก้ `CODEX_TIMEOUT_SEC=8` ในสำเนาที่ติดตั้ง | exit 8 (`rc=timeout`), BLOCKED |
| `13ccffd5` | 11:28:01 | `/delegate resume` (เซสชันใหม่) | หยุดถามก่อน ผู้ใช้เลือกข้อ 1 แล้วรันรอบ 2 PASS, DONE |

ผลที่ได้คือ commit `ab85769` (sub), `af63865` (mul), `bcfd46e` (div) บนสาขา `ai/delegate-20261008-1120`, unittest 4 ตัวผ่าน, ไม่มี push, ไม่มี `.lock` หรือ `.timed-out` ค้างในโฟลเดอร์รันทั้งสอง Codex ใช้เวลา 38, 29 และ 33 วินาทีในรอบที่สำเร็จ

**Resume หลัง `rc=interrupted` (กฎ Resume ข้อ 2 และ 4): ผ่าน**

- Claude ตรวจ `git branch --show-current`, `git rev-parse HEAD`, `git status --porcelain` (ว่าง), `count` = 1, `pgrep` ไม่พบ process และ `check-status` ได้ exit 7 (`MISMATCH codex_runs: status.md says '0', the ledger (runs.log) says 1`) จึงแก้ status.md ให้ตรงกับ ledger และแจ้งผู้ใช้ว่าค่าเดิมค้าง status.md ค้างเพราะการกด Esc ตัดการเรียก Bash ก่อนที่ Claude จะคัดลอก `runs_total` ซึ่งเป็นกรณีที่ออกแบบให้ ledger ชนะไว้แล้ว
- รัน preflight ข้อ 3-4 ซ้ำ (`codex --version`, `codex login status`, `codex exec --help`, `version` = 4.4) แล้วรัน slice 01 รอบ 1 ด้วย brief เดิม ไม่เปลี่ยนเลขรอบ (`runs_total=2/12`) ตรงตามกฎข้อ 4
- ตอนจบ `check-status` exit 0 (`codex_runs=3, ledger=3`) รายงานว่าครั้งที่ถูกขัดจังหวะนับรวมด้วย
- คำแนะนำการยกเลิก: task_branch ต่างจาก original_branch (`master`) จึงแนะนำ "สลับไป master แล้วลบสาขางาน" ถูกต้องตาม v4.2

**เส้นทาง timeout (exit 8) กับ Codex จริง: ผ่าน**

- Bash timeout ของการเรียกนั้นตั้งเป็น 68000 ms = (8 + 60) × 1000 ตามสูตรใน SKILL.md
- สคริปต์หยุด Codex ที่ 8 วินาที (exit 8, ledger `rc=timeout result_bytes=0`) log มีเพียงข้อความว่า Codex เริ่มอ่าน slice ยังไม่ได้แก้ไฟล์ใด
- Claude รัน `pgrep` (ไม่พบ) และ `git status --porcelain` (ว่าง), เขียน review บรรทัดแรก `verdict: BLOCKED` พร้อมสาเหตุ, ตั้ง state เป็น BLOCKED, รัน `check-status` (exit 0) ก่อนรายงาน BLOCKED และไม่รันซ้ำเอง

**Resume หลัง `rc=timeout` และ state BLOCKED (กฎ Resume ข้อ 3 ที่เพิ่มใน v4.3): ผ่าน**

- Claude ตรวจครบ (`check-status` exit 0, `pgrep` ไม่พบ, tree สะอาด, HEAD ตรงกับที่บันทึก) แล้ว **หยุดถามโดยไม่รันเอง** เสนอ 3 ทาง: ใช้ 540 วินาทีแล้วรันซ้ำ / ตั้งค่าอื่น / เปลี่ยน brief หรือแบ่ง slice ใหม่ ผู้ใช้ตอบ "1" หลังจากนั้น 8 นาที
- Claude สร้าง `task-01-r2.md` จากรอบ 1 (เปลี่ยนเฉพาะหัวเรื่องด้วย `sed ... > ไฟล์`) แล้วรันเป็น **รอบ 2** ด้วย `--timeout-sec 540` และ Bash timeout 600000 และแก้บรรทัด `config:` ใน status.md เป็น `timeout_sec=540` ผล PASS
- คำแนะนำการยกเลิก: run นี้ต่อยอดบนสาขา `ai/` เดิม (task_branch เท่ากับ original_branch) Claude บอกว่าห้ามลบสาขา และการ `git reset --hard <INITIAL_BASE>` ผู้ใช้ต้องตัดสินใจเอง Claude ไม่ได้รันเอง ตรงกับข้อความที่ v4.2 กำหนด

**pattern ของ `pgrep` ใน v4.4 บน macOS จริง** (ตรวจบน Mac ของผู้ใช้เมื่อ 2026-10-09 ขณะ ChatGPT desktop app เปิดอยู่): `pgrep -fl "codex exec"` แบบเก่าจับ `.../ChatGPT.app/.../codex exec-server --remote ...` (จับผิดตัว) ส่วน pattern ใหม่ไม่จับอะไร (rc=1) daemon `app-server` ตอนนี้เป็นรุ่น 0.162.0 `bash tests/run_tests.sh` บน Mac เครื่องเดียวกันได้ 61 passed, 0 failed (รวม T14) ส่วนการที่ pattern ใหม่จับ process ของ `delegate-run.sh` ตัวจริงบน macOS ได้ (true positive) ยังทดสอบเฉพาะด้วย process จำลองใน T14

**ข้อสังเกตและข้อบกพร่องที่พบ (ยังไม่ได้แก้ใน kit)**

1. **ต่อคำสั่งด้วย `cd` ทำให้ cwd เปลี่ยน:** ในเซสชัน resume แรก Claude รัน `cd .ai/20261008-1120 && cat ... && ...` ซึ่งผิดกฎ "Run each Bash command as its own call" และ cwd ของ Bash ใน Claude Code คงอยู่ข้ามคำสั่ง คำสั่ง `delegate-run.sh count` ถัดมาจึงล้มด้วย exit 2 (`run from the repo root ... not from .../.ai/20261008-1120`) ซึ่ง `need_repo_root` กันไว้ได้ Claude แก้ด้วยการต่อ `cd <repo root> && ...` นำหน้า (ผิดกฎเดิมอีก) แล้วกลับมาที่ root ได้ ไม่มีผลเสียต่องาน แต่ทำให้เกิด permission prompt และเสี่ยงที่คำสั่ง git จะรันผิดโฟลเดอร์ (คำสั่ง git ช่วงนั้นรันจาก `.ai/20261008-1120` และได้ผลถูกเพราะ git หา repo จากโฟลเดอร์ย่อยได้) ข้อเสนอสำหรับรุ่นถัดไป: เพิ่มในกฎว่า "ห้ามใช้ `cd` ให้อ่านไฟล์ด้วย path ที่นับจาก root ของ repo"
2. **ไม่ได้กำหนดเลขรอบหลัง BLOCKED จาก timeout:** กฎ Resume ข้อ 3 ให้ถามผู้ใช้ แต่ไม่ระบุว่ารอบถัดไปใช้เลขเดิมหรือ R+1 Claude เลือก R+1 จึงกินหนึ่งรอบของ `MAX_ROUNDS_PER_SLICE` (3) ทั้งที่รอบแรกไม่มีผลงาน ส่วนกรณี `rc=interrupted` กฎข้อ 4 ให้ใช้เลขเดิม สคริปต์รับได้ทั้งสองแบบเพราะรอบเดิมไม่มีไฟล์ result ควรกำหนดให้ชัด brief รอบ 2 ไม่มีหัวข้อ "Findings to fix" ซึ่งสมเหตุสมผลเพราะไม่ใช่ FAIL
3. **ค่าที่ใช้จริงต่างจากบล็อก Configuration ที่โหลด:** SKILL.md ที่โหลดในเซสชัน `13ccffd5` ยังตั้งไว้ 8 วินาที Claude ใช้ 540 ตามคำตอบของผู้ใช้ในแชตและบันทึกไว้ใน status.md ถือว่ายอมรับได้เพราะผู้ใช้เลือกเอง แต่ SKILL.md ไม่ได้ระบุว่าคำตอบในแชตทับค่า Configuration ได้
4. **สำเนาที่ติดตั้งต่างจาก kit:** `~/.claude/skills/delegate/SKILL.md` ถูกแก้เมื่อ 2026-10-08 11:58:08 (หลังการทดสอบทั้งหมด) เป็น `CODEX_TIMEOUT_SEC=1500` พร้อมคอมเมนต์ว่าต้องมี `BASH_MAX_TIMEOUT_MS >= 1560000` (`~/.claude/settings.json` ของเครื่องนี้ตั้ง 1800000 แล้ว) แต่ใน kit ยังเป็น 540 ผลคือ `bash install.sh` จะปฏิเสธ (exit 2) และ `--force` จะเขียนทับกลับเป็น 540 (มีไฟล์สำรอง) ต้องถามผู้ใช้ก่อนว่าจะยกค่า 1500 เข้า kit หรือไม่ (ตามหัวข้อ 7: ถามก่อนเปลี่ยนค่า default) ค่า 8 วินาทีที่ใช้ทดสอบไม่มีอยู่ในไฟล์สำรองใด เพราะแก้ในสำเนาที่ติดตั้งโดยตรงหลัง 11:13
5. Codex ยังอ่าน `ponytail` SKILL.md จาก plugin cache (บันทึกใน `review-02-r1.md` ของ run `20261008-1120`) diff ไม่ได้รับผลกระทบ แต่ยังสรุปไม่ได้ว่าบรรทัดเรื่องลำดับความสำคัญใน brief ได้ผล
6. Codex ตั้ง `PYTHONDONTWRITEBYTECODE=1` เองตอนรันเทสต์ เพื่อไม่ให้เกิดไฟล์ที่อยู่นอกขอบเขต (`result-01-r2.md` ของ run `20261008-1126`)

**สถานะการทดสอบหลังหัวข้อนี้**

- ทดสอบแล้ว (ตัดออกจากรายการค้าง): `/delegate resume` ในเซสชันใหม่, กฎ Resume ข้อ 2-4 ของ v4.3 (`rc=interrupted` และ `rc=timeout` + BLOCKED), BLOCKED จาก timeout (exit 8) กับ Codex จริง, pattern `pgrep` ไม่จับ process ของ desktop app บน macOS, ข้อความการยกเลิกทั้งสองแบบของ v4.2
- ยังไม่ได้ทดสอบ: รอบ FAIL แล้วแก้รอบที่ 2 ด้วย "Findings to fix", การหยุดเมื่อไม่มีความคืบหน้า, exit 9 กับ Codex จริง, resume เมื่อ END ล่าสุดเป็น rc ไม่เป็นศูนย์ (exit 5) หรือเมื่อมี START ที่ไม่มี END, `pgrep` จับ process ของ `delegate-run.sh` ตัวจริงบน macOS, กฎ deny `Edit(.ai/*/runs.log)` และ allow รูปแบบ `~` กับ Claude Code จริง
- ข้อ 1-3 ข้างบนเป็นตัวเลือกของ v4.5 (แก้เฉพาะข้อความใน SKILL.md) ข้อ 4 ต้องให้ผู้ใช้ตัดสินใจก่อน

