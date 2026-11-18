# Gemini Windows integration

Status: implemented and detected on this machine. The live session list, stable conversation URLs, and existing user/assistant message bodies were read. The new-chat page exposes a ValuePattern composer and an InvokePattern send button. No quota-consuming live message has been sent yet.

| Action | Channel | Evidence | Limit |
| --- | --- | --- | --- |
| Read list and history | Windows UI Automation | Gemini conversation links and semantic user/assistant groups expose stable URLs and message bodies | History is loaded when the conversation is opened |
| Send | Windows UI Automation, Value + Invoke patterns | unique `Enter a prompt for Gemini` and `Send message` controls | Attachments and model selection stay in Gemini |
| Stop | Windows UI Automation | profile recognises Stop response | Not live-tested |
| New chat | Windows UI Automation | unique navigation New chat link | Not live-tested |
| Settings/cards/files | none | no verified stable control path | use Gemini desktop |

Resume: open Gemini, run `npm start`, then use the Gemini entry. A real send still needs the user's consent.
