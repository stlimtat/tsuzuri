# Renders are AI-acted videos of consecutive Panels, made in the cloud on request, watched only in the app

A Render is a short AI-generated video, with the model's own voiced dialogue, in which one or more consecutive Panels are acted out, made by a cloud video model only when a paying user asks. Acting needs context from several Panels, Characters must look and sound consistent across Renders, and context established in earlier Panels must carry forward; device TTS was rejected because it cannot carry the acting. Its purpose is to wow: to show how a Panel would look acted on screen. A simple on-device camera pan over the still Panel was prototyped and rejected as unimpressive. Renders are requested individually for short runs of Panels so a bad result costs one re-render, never a whole Chapter, and they play only inside the Player, with no export or share. That keeps the product a reading aid rather than a manga-to-video tool and supports a personal-viewing stance for copyright and App Store review. Renders are backed up to the user's iCloud.

## Considered Options
- On-device Render (camera pan, subtitles, Apple voice): rejected after a prototype, not impressive enough to sell
- One exportable video per Chapter: rejected; errors force long re-renders and it invites re-uploading copyrighted manga

## Consequences
- Every Render costs real money (cloud video is priced per second), so Renders are paid-only and never free.
- Panel images are sent to a third-party video provider; this needs explicit consent and provider choice by retention policy.
- Generation is slow (minutes), so Renders are asynchronous jobs.
