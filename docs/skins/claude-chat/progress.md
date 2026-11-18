# Claude Windows chat integration

Status: installed but blocked by the desktop login page. The integration reports the sign-in requirement instead of pretending it is connected.

| Action | Channel | Evidence | Limit |
| --- | --- | --- | --- |
| Read list | Windows UI Automation | signed-in desktop detected; the current account currently exposes only the new-chat page | account verification is still required by Claude |
| Send / stop / new | Windows UI Automation | Chinese and English composer/new/send labels are covered | blocked while Claude says the account cannot use replies |
| Settings/cards/files | none | no verified stable control path | use Claude desktop |

Resume: complete the Anthropic verification shown in the Claude desktop window, reopen Frontdesk, then probe a populated chat before a real send.
