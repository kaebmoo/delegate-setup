# HANDOFF: ชุดไฟล์ /delegate (Claude วางแผนและตรวจรับ, Codex เขียนโค้ด)

เอกสารนี้สำหรับ Claude เซสชันถัดไป (Cowork) และสำหรับผู้ใช้ ใช้ต่องานจากจุดที่ค้างโดยไม่ต้องอ่านบทสนทนาเดิม

## 1. สิ่งที่ทำเสร็จแล้ว

| ไฟล์ | หน้าที่ |
|---|---|
| `delegate/SKILL.md` | คำสั่ง `/delegate` ระดับผู้ใช้ มีวงจร preflight, plan, slice loop, review, finish และ resume |
| `settings.snippet.json` | ค่า permissions (allow/deny) และ env สำหรับ `~/.claude/settings.json` |
| `repo-templates/AGENTS.md` | แม่แบบกติกาของ repo ที่ทั้ง Codex และ Claude อ่าน |
| `repo-templates/CLAUDE.md.snippet` | import `@AGENTS.md` และกติกา "เรียก Codex เฉพาะเมื่อพิมพ์ /delegate" |
| `merge-settings.js` | รวม `settings.snippet.json` เข้า `~/.claude/settings.json` ด้วย Node: สำรองไฟล์เดิม, ไม่ลบหรือทับรายการเดิม, ทำซ้ำได้โดยไม่เพิ่มซ้ำ, ถ้า JSON เดิมเสียจะไม่แตะอะไร (มี `--dry-run`) |
| `install.sh` | ติดตั้ง SKILL.md ไปที่ `~/.claude/skills/delegate/` โดยไม่ลบ ไม่แตะ settings.json และไม่เขียนทับไฟล์ที่ต่างกันถ้าไม่ใช้ `--force` |

## 2. การตัดสินใจออกแบบและเหตุผล

- **ทุกรอบเรียก `codex exec` ใหม่ด้วย brief ไฟล์ใหม่ ไม่ใช้ `resume`** ทดสอบกับ CLI จริงแล้วพบว่า `codex exec resume` ไม่มี `--sandbox` และไม่มี `--cd` จึงยืนยันไม่ได้ว่า sandbox คงเดิม วิธีนี้ยังตรวจสอบย้อนหลังได้ทุกรอบ
- **`.ai/` ซ่อนตัวเองด้วย `.ai/.gitignore` ที่มีบรรทัด `*`** แทนการแก้ `.git/info/exclude` เพราะไม่ต้องแตะ `.git` (ซึ่ง Claude Code ถือเป็น protected path และจะถามสิทธิ์) และใช้ได้กับ git worktree ทดสอบแล้ว
- **ถามยืนยันครั้งเดียวต่อ repo ก่อนส่งโค้ดให้ Codex** (ไฟล์ `.ai/external-ok`) เพราะ Codex อ่านไฟล์แล้วส่งเนื้อหาไป OpenAI ซึ่งย้อนคืนไม่ได้
- **ตรวจ `codex login status` จากข้อความ ไม่ใช่ exit code** เพราะทดสอบแล้วได้ exit 0 แม้พิมพ์ "Not logged in"
- **ใช้ Bash timeout ของ Claude Code แทน `timeout` ของระบบ** เพราะ macOS ไม่มี `timeout` มาให้ และ Codex ที่ยังไม่ล็อกอินจะค้างเงียบ ๆ ไม่ error (ทดสอบแล้ว: ต้องถูกตัดด้วย timeout และไม่เกิดไฟล์ผลลัพธ์) skill จึงถือว่าไม่มีไฟล์ผลลัพธ์เท่ากับ BLOCKED
- **Claude แก้เองได้เฉพาะ mechanical fix** (ไม่เกิน 5 บรรทัด, ไม่เปลี่ยนพฤติกรรม, บันทึกใน review) ตั้ง `CLAUDE_MECHANICAL_FIXES=deny` ถ้าต้องการความเป็นอิสระของผู้ตรวจเต็มรูปแบบ
- **เพดาน:** 3 รอบต่อชุดงาน, 12 การเรียก Codex ต่อหนึ่งรอบ /delegate, หยุดทันทีเมื่อพบปัญหาเดิมซ้ำสองรอบ แก้ได้ที่บล็อก Configuration ต้นไฟล์ SKILL.md
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

1. **ยังไม่เคยรันกับ Codex จริงจนจบหนึ่งรอบ** เครื่องทดสอบไม่มี auth ต้องทดสอบบน Mac (ดูหัวข้อ 5)
2. **ชื่อโมเดลที่ใช้ได้กับบัญชีของคุณ** บล็อก Configuration ตั้ง `CODEX_MODEL` ว่างไว้ (ใช้ default ของ Codex) เอกสารระบุ `gpt-6.1-sol` เป็นตัวอย่างเท่านั้น ไม่ใช่รายการยืนยัน ให้ตรวจจาก Codex เองบนเครื่อง แล้วค่อยล็อกค่า
3. **ข้อความของ `codex login status` เมื่อล็อกอินแล้ว** skill สมมติว่ามีคำว่า `Logged in` (ทดสอบได้เฉพาะกรณี `Not logged in`) ถ้าข้อความจริงต่างออกไป ให้ปรับ preflight ข้อ 3
4. **`CODEX_EFFORT=high`** Codex parse ได้ แต่ยังไม่ยืนยันว่าโมเดลที่เลือกรับค่านี้
5. **การทำงานของ SKILL.md ใน Claude Code จริง** ยังไม่ได้ทดสอบว่า `/delegate` ปรากฏในเมนู, ข้อความงานที่พิมพ์หลัง `/delegate` ไปถึง Claude (ตามเอกสารจะถูกต่อท้ายไฟล์เป็นบรรทัด `ARGUMENTS:`) และ Claude ทำตามขั้นตอนครบ
6. **Permission prompt** การเขียนไฟล์ใน `.ai/` ครอบด้วย `Edit(.ai/**)` แล้ว แต่คำสั่งทดสอบ/lint ของแต่ละโปรเจกต์ต้องเพิ่มใน `.claude/settings.local.json` ของ repo นั้น หรือใช้โหมด acceptEdits มิฉะนั้นวงจรจะหยุดรอการอนุมัติ
7. **เพดานเวลา** ค่า `CODEX_TIMEOUT_MS=600000` ใช้ได้กับ settings เริ่มต้น หากต้องการนานกว่านี้ให้ merge บล็อก `env` ใน snippet แล้วค่อยเพิ่มค่าใน SKILL.md
8. **ตัวเลือกที่ยังไม่ได้ผนวก:** `codex exec review` (มีใน 0.160.1) ใช้เป็นความเห็นที่สองได้, `--ephemeral` ถ้าไม่ต้องการให้ Codex เก็บ session ไฟล์
9. **ข้อจำกัดของ skill ระดับผู้ใช้:** ใช้ไม่ได้ใน Cowork หรือ cloud session ต้องรัน `claude` บน Mac โดยตรง
10. ใน sandbox ทดสอบ `./install.sh` รันตรงไม่ได้ (mount ไม่ให้ execute) ใช้ `bash install.sh` แทน บน Mac ปกติไม่น่ามีปัญหานี้

## 5. แผนทดสอบบน Mac (ทำตามลำดับ หยุดทันทีถ้าข้อใดไม่ผ่าน)

1. ติดตั้ง Codex CLI และล็อกอินเอง (`codex login`) แล้วตรวจ `codex login status` จดข้อความที่ได้ไว้ (ข้อ 4.3)
2. `bash install.sh` แล้วรัน `node merge-settings.js --dry-run` เพื่อดูตัวอย่าง จากนั้นรัน `node merge-settings.js` จริง
3. สร้าง repo ทดสอบเล็ก ๆ: ไฟล์ `src/app.py` ที่มีฟังก์ชัน `add` คืนค่าผิด และ `tests/test_app.py` ที่ fail commit ไว้ แล้วคัดลอก `repo-templates/AGENTS.md` ไปปรับคำสั่งทดสอบ
4. `cd` เข้า repo, เปิด `claude`, พิมพ์ `/delegate แก้ฟังก์ชัน add ให้ผ่าน tests/test_app.py` (ใช้ข้อมูลตัวอย่างเท่านั้น)
5. สิ่งที่ต้องเห็น: ถามยืนยันส่งข้อมูลหนึ่งครั้ง, สร้าง branch `ai/delegate-<RUN>`, สร้าง `.ai/<RUN>/` พร้อม plan และ task-01-r1.md, เรียก `codex exec` ตามรูปแบบใน SKILL.md, review ไฟล์มีคำสั่งที่รันและ exit code, commit บน branch, ไม่มี push, `git status` สะอาด
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
- ถ้าแก้ SKILL.md ให้รัน `bash -n install.sh` และตรวจ JSON ของ snippet อีกครั้ง และตรวจ SKILL.md ด้วย `python3 -I /mnt/skills/examples/skill-creator/scripts/quick_validate.py <โฟลเดอร์ของ skill>` (โฟลเดอร์ที่มี SKILL.md อยู่) ต้องได้ "Skill is valid!"
- frontmatter ต้องมีเฉพาะ `name`, `description`, `compatibility` (คีย์อื่นถูกปฏิเสธตอนอัปโหลด) และ description ต้องไม่มีเครื่องหมาย `<` หรือ `>` ส่วนเนื้อหาด้านล่างใช้ได้ตามปกติ
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
