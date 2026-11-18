# Doubao Windows integration

Status: implemented and detected on this machine. The live read-only session list matches the Doubao sidebar. A draft was inserted and removed without sending; no quota-consuming live message has been sent yet. Historical-body reconstruction is pending a read-only inspection while Doubao is open on a populated chat.

| Action | Channel | Evidence | Limit |
| --- | --- | --- | --- |
| Read list and history | Windows UI Automation | conversation links expose stable URLs and titles; the virtual message list is paged read-only and restored to the bottom | At most 24 reconstructed messages per read; unloaded gaps are skipped instead of guessed |
| Send | Windows UI Automation, Value/Text + Invoke patterns | composer and `flow-end-msg-send` are unique; foreground window stayed unchanged in the draft probe | Attachments and settings stay in Doubao |
| Stop | Windows UI Automation | profile recognises the desktop Stop button | Not live-tested |
| New chat | Windows UI Automation | desktop New chat button | Not live-tested |
| Settings/cards/files | none | no verified stable control path | use Doubao desktop |

Resume: sign in and open Doubao, run `npm start`, then use the Doubao entry. A real send still needs the user's consent.
