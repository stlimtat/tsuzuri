# On-device first; cloud only where the device can't do the job, and cloud use is always paid

Everything the device can do is free: import, Library, Panel editing, OCR of horizontal text (Vision), translation (Apple Translation) and Read-aloud with Apple voices. The cloud is used only where on-device quality is not good enough, namely OCR of vertical Japanese text, which Apple Vision handles poorly, and Renders, which need cloud video models. Every cloud call is paid by the user, so cloud usage never has to be subsidised and the backend stays small. A future reader may wonder why horizontal and vertical text take different paths: that split is the price boundary, not a technical accident.

## Consequences
- Text orientation must be known per Bubble before any cloud call.
- Free users get a complete experience on horizontal-text comics; vertical-text Japanese manga and Renders are the paid upsell.
