# Day 46 - Reusable Workflows & Composite Actions

## Task 1: Understanding workflow_call

**Q: Reusable workflow kya hai?**
Ek complete workflow file jise doosri workflows "call" kar sakti hain,
jaise ek function ko call karte hain. Isme jobs, steps, inputs, outputs
define hote hain, aur multiple repos/workflows ise reuse kar sakte hain.

**Q: workflow_call trigger kya hai?**
Ek special trigger (`on: workflow_call`) jo batata hai ki ye workflow
push/PR se nahi chalegi — sirf tab chalegi jab koi doosri workflow
ise explicitly call kare.

**Q: Regular action (uses:) vs reusable workflow mein difference?**
- Regular action = ek single STEP, ek job ke andar chalta hai
- Reusable workflow = poori JOB replace karta hai, apne andar
  multiple jobs/steps ho sakte hain

**Q: Reusable workflow file kaha honi chahiye?**
`.github/workflows/` directory mein hi — same jagah jaha normal
workflows rehti hain.