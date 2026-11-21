---
name: play-store-aso
description: Audit and optimise a Google Play Store listing for one of the owner's apps. Research competitors and search intents, audit metadata and visual assets, identify ASO opportunities, rewrite title / short / full description, validate claims and character limits, then optionally update Play Console via Claude in Chrome. Use for "improve my Play Store listing", "ASO", "optimise store listing", "store description", "Play Store keywords", "update listing in Play Console".
---

# Play Store ASO

## Goal

Maximise relevant Google Play discovery and store-listing conversion.

The objective is not simply to insert keywords into descriptions. A good listing must:

1. Match the search intents of the intended audience.
2. Communicate the application's value immediately.
3. Differentiate the product from competing applications.
4. Convert relevant visitors into installs.
5. Set accurate expectations about the actual product.

ASO includes metadata, visual assets, localisation, ratings, technical quality and experimentation.

Google does not publish its complete search-ranking algorithm or keyword-weighting formula. Never present undocumented ranking theories as confirmed Google ranking factors.

Read `references/aso-rules.md` before conducting research or writing copy.

## Operating principles

- Base every product claim on the actual application or verified project data.
- Distinguish Google Play requirements from ASO recommendations and hypotheses.
- Never invent search volumes, ranking positions, competitor metrics or performance data.
- Never use fixed keyword repetition quotas.
- Never sacrifice readability to include keywords.
- Audit visual assets as part of the listing, even when the requested implementation is copy-only.
- Keep existing listing files. Write new versions alongside them.
- Do not modify the live listing without the user's approval.
- Saving a draft is not publishing. Submitting changes for review requires separate, explicit approval.

## 1. Gather application information (local, read-only)

Identify the application.

- Find `applicationId` in `android/app/build.gradle.kts` or `build.gradle`.
- Account for product flavors, application ID suffixes and build variants.
- Verify the identifier against the existing Play Store listing or Play Console when possible.
- Never assume the package name based only on the project directory.

Inspect existing documentation:

- `docs/play-store/`
- `listing-*.txt`
- `README.md`
- `assets/`
- Existing translations and marketing materials.

Inspect the actual application and its source code to establish its positioning and capabilities.

Collect verifiable facts:

- Main functionality and differentiating features.
- Content counts, categories, bundles and game modes.
- Supported languages.
- Supported Android versions and devices.
- Offline or online functionality.
- Monetisation: ads, subscriptions and IAP.
- Permissions and important privacy-related behaviours.
- Account requirements.
- Current version and release status.

Count content from actual data files (JSON, databases, assets, etc.), never guess numbers.

Round down when expressing quantities where appropriate ("over 80", "1,000+"). Keep exact figures available as evidence.

For each important marketing claim, identify its source in the repository or application.

**Important:** Supported app UI languages and available Play Store listing translations are different things. Record them separately.

Do not change application code as part of an ASO task.

## 2. Audit the live listing (Chrome, read-only)

Open:

`https://play.google.com/store/apps/details?id=<applicationId>`

Use `get_page_text` and inspect the available listing content.

Record:

- App title.
- Short description.
- Full description.
- Category.
- Public rating and number of ratings.
- Public install range, when displayed.
- Last update, when available.
- Public screenshots.
- Feature graphic, when accessible.
- Preview video, when available.

Inspect the actual visual assets rather than evaluating them only from their descriptions.

If information is unavailable on the public listing, do not infer it. Use the owner's Play Console session where appropriate.

### Audit existing listings

Check:

- Default listing.
- Existing translated listings.
- Existing Custom Store Listings.
- Existing search-keyword targeting.
- Existing listing experiments, if visible.

Do not silently replace a translated or custom listing with the default listing's copy.

### Evaluate positioning

Determine whether the current listing clearly communicates:

- What the application does.
- Who it is for.
- Its main benefit.
- Its distinguishing functionality.
- Why someone should choose it over alternatives.

Identify mismatches between the marketing promises and actual product experience.

### Rating and review audit

Report the current rating and review count.

Where possible, inspect recurring feedback themes:

- Bugs and crashes.
- Missing functionality.
- Confusing UX.
- Performance issues.
- Misleading expectations.

Do not apply an arbitrary rating threshold such as 4.2 stars. A rating is contextual and should be assessed alongside its volume, trends and feedback.

Do not recommend encouraging users to include keywords in reviews.

### Visual audit

Assess the following assets:

**Icon**
- Recognition at small sizes.
- Brand identity.
- Differentiation from competitors.
- Visual clarity.

**Screenshots**
- Does the first screenshot communicate the core value?
- Is the real application experience visible?
- Is the sequence persuasive and coherent?
- Are the features understandable?
- Is the text readable on mobile?
- Are there misleading or repetitive images?
- Are assets appropriate for each target language?

**Feature graphic**
- Does it communicate the core product proposition?
- Is it visually consistent with the icon and screenshots?
- Does it meet current Google Play requirements?

**Preview video**
- Does it show the actual product?
- Is the core experience demonstrated immediately?
- Does it work without sound?
- Is there unnecessary introductory content?

Do not flag missing screenshot captions as an ASO problem. Captions are optional and should only be used when they improve understanding.

Do not treat promotional text as a keyword-indexing mechanism.

If assets cannot be inspected, explicitly report the limitation.

## 3. Research competitors and search intents

Before writing copy, understand the competitive landscape.

### 3.1 Identify competitors

Use Google Play search for relevant queries.

Identify approximately five relevant competing applications, prioritising apps that:

- Target the same audience.
- Offer similar functionality.
- Compete for the same search intents.
- Have comparable positioning.

Inspect their:

- Titles.
- Short descriptions.
- Full descriptions.
- Icons.
- Screenshots.
- Feature graphics.
- Preview videos.
- Ratings and review themes.
- Recent updates.

Record competitor names and Play Store links.

Search results differ by country, language, device and personalisation. Record the market and language used for research.

Do not assume that appearing first in one search proves a universal ranking position.

Do not copy competitor marketing text.

### 3.2 Build a keyword opportunity map

Identify relevant search intents rather than generating arbitrary keyword lists.

Typical intent categories:

| Intent | Example |
|---|---|
| Category | Brain training games |
| Functionality | Mental math games |
| Specific mechanics | Fast arithmetic battles |
| Content | Actual game modes or features |
| Audience | Relevant user groups |
| Use case | Offline games, daily training, etc. |

For each opportunity, record:

- Search phrase.
- Search intent.
- Relevance to the actual application.
- Evidence or research source.
- Competing applications observed.
- Recommended destination in the listing.
- Confidence in the opportunity.

Use ASO research tools where available, such as AppTweak or MobileAction.

If reliable search-volume data is unavailable, say so. Never fabricate volumes, difficulty scores or estimated ranking positions.

Do not assume that every relevant phrase must be inserted into the full description.

### 3.3 Evaluate Custom Store Listings

Google Play supports Custom Store Listings, including targeting by search keywords, countries, audiences and campaigns.

Consider whether the application has multiple meaningful search intents that deserve different positioning.

For example, a game might attract users through both "brain training" and "math games". Different custom listings could communicate different aspects of the same product.

Recommend this only when:

- Search intents are genuinely distinct.
- Different messaging or assets can improve relevance.
- There is sufficient traffic to justify maintaining alternatives.

Google supports up to 50 Custom Store Listings.

Do not create them automatically during a standard metadata update.

## 4. Produce an ASO opportunity report

Before writing copy, present a concise audit.

Include:

### Current positioning
What the app currently communicates and where its messaging is weak.

### Competitive landscape
Relevant competitors and the most important positioning differences.

### Keyword opportunities
Relevant search intents, evidence and recommended placement.

### Conversion audit
Icon, feature graphic, screenshots, video and localisation.

### Prioritised actions

Classify recommendations by:

- Expected impact: high / medium / low.
- Confidence: high / medium / low.
- Implementation effort: high / medium / low.

Separate factual problems from hypotheses that require testing.

Do not automatically recommend rewriting everything. Retain existing elements when they already perform their job well.

## 5. Write the listing copy

Write new drafts to:

`docs/play-store/listing-<locale>-aso.txt`

Never overwrite the previous listing file.

Use these sections:

- APP NAME (max 30)
- SHORT DESCRIPTION (max 80)
- FULL DESCRIPTION (max 4000)

What's New is optional and must be handled separately as release notes, not as part of the permanent listing.

### Title

Generate three alternatives when the current positioning needs improvement:

1. Brand-first.
2. Brand plus descriptive category/functionality.
3. Descriptive title, where appropriate.

Evaluate each on:

- Brand recognition.
- Search relevance.
- Clarity.
- Differentiation.
- Character limit.

A `Brand: Keyword` structure is a possible approach, not a universal requirement.

Do not fill the character limit just to use all available space.

Avoid misleading claims, promotional language and unnecessary special characters.

### Short description

- Communicate what the app does.
- Explain its strongest benefit or differentiator.
- Use relevant terminology naturally.
- Make the proposition immediately understandable.
- Avoid a pure tagline that says nothing about the actual product.
- Avoid generic marketing expressions.
- Do not insert unnecessary keywords for search ranking.

Provide alternative formulations when useful.

### Full description

Structure the description for people, not keyword-density algorithms.

Recommended structure:

1. Opening: clearly explain what the app is and its main value.
2. Core features: describe the most important functionality.
3. Differentiators: explain what makes the experience distinct.
4. Additional functionality: relevant modes, categories, content and capabilities.
5. Practical details: offline support, accounts, supported functionality, etc., when relevant.

Rules:

- Put the most important information near the beginning.
- Use readable sections and bullets.
- Incorporate relevant terminology naturally.
- Never follow a fixed keyword repetition quota.
- Avoid keyword stuffing and repetitive synonyms.
- Never include unsupported content counts or functionality.
- Do not add irrelevant competitor names or famous IP solely for search exposure.
- Avoid unnecessary marketing language.
- Ensure the text matches the actual product.

### Character limits and validation

Google Play metadata limits:

| Field | Maximum |
|---|---:|
| App name | 30 |
| Short description | 80 |
| Full description | 4,000 |
| What's New | 500 per language |

Verify lengths with a script rather than by eye.

Example:

```python
fields = {
    "APP NAME (max 30)": 30,
    "SHORT DESCRIPTION (max 80)": 80,
    "FULL DESCRIPTION (max 4000)": 4000,
}

# Adapt extraction to the actual section headings in the draft.
for name, limit in fields.items():
    value = sections[name].strip()
    count = len(value)
    status = "OK" if count <= limit else "OVER LIMIT"
    print(f"{name}: {count}/{limit} - {status}")
```

Use the Play Console's own character counters as the final verification. Pay particular attention to Unicode characters and emojis.

Edit the file with the Edit tool, not `sed -i` (macOS BSD sed requires a suffix).

### Review the draft

Before showing it to the user:

- Check every claim against gathered evidence.
- Check the title and short description against their limits.
- Check natural keyword coverage.
- Check grammar and localisation.
- Compare with the current listing to identify meaningful changes.
- Ensure the listing accurately represents the application.

Show the user:

1. The ASO opportunity report.
2. The proposed title alternatives.
3. The proposed short description.
4. The complete full description.
5. Character counts.
6. Any unresolved assumptions.

Ask for approval before pushing changes to Play Console.

## 6. Push copy to Play Console (Chrome, user's session)

Only proceed after the user approves the proposed copy.

### Load Chrome tools

Load the following tools in one ToolSearch:

`tabs_context_mcp, navigate, computer, read_page, find, form_input, get_page_text, javascript_tool`

### Account verification

Navigate to:

`https://play.google.com/console`

Gotchas:

- `/u/0/` may be a different Google account and display the developer-account signup screen.
- Never click through an account creation flow.
- Try `https://play.google.com/console/u/1/developers` (account index varies).
- Use the "Choose developer account" picker and select the owner's existing account.
- If the correct account cannot be established, stop and ask the user to switch accounts.

Verify the selected application using its package name before editing.

### Navigate to the listing

Deep links to the listing editor may redirect to Home.

Use the normal interface:

1. Home.
2. Application row.
3. Click the row's arrow button.
4. Application dashboard.
5. Store presence / Store listings.
6. Edit default listing.

Existing automation gotchas:

- Clicking app row title text may not navigate; click its arrow button.
- On Store listings page, locate the appropriate edit link.
- JavaScript navigation can be used for discovered links, for example:

`[...document.querySelectorAll('a[href$="/store-listings/default/edit"]')][0].click()`

Never assume that the default listing is the correct locale when the user requested another language.

### Fill and save

Use `find` to identify:

- App name.
- Short description.
- Full description.

Use `form_input` on the corresponding references.

Verify the updated counters. For example:

- `30 / 30`
- `74 / 80`
- `N / 4000`

Re-run `find` and inspect the fields after filling them.

Do not modify screenshots, icon, feature graphic, video or translated listings unless explicitly included in the approved scope.

Click **Save as draft**.

Verify the success notification ("Draft saved").

Stop here and report the draft status.

**Saving a draft does not require submission approval.**

## 7. Submit for review (explicit approval required every time)

Submitting changes for review is an outward-facing action.

Never do this automatically after saving a draft.

Before requesting approval, explain:

- Which fields are being submitted.
- Which listing and locale are affected.
- Whether other changes are pending.
- Whether Managed Publishing is enabled.
- Whether approval by Google will automatically make the changes public.

Important:

When Managed Publishing is disabled, approved changes can become public automatically. Managed Publishing can hold approved changes for separate publication, but is not available for a first-time app publication.

If the consequences are unclear, stop and explain them rather than assuming.

After explicit approval:

1. On the edit page click **Next**.
2. Review the resulting listing.
3. Click **Save**.
4. Navigate to Publishing overview, for example:
   `.../app/<id>/publishing`
5. Verify that the listed changes match the approved draft.
6. Click **Submit N changes for review**.
7. Verify the confirmation dialog.
8. Click **Send changes for review**.
9. Confirm the success notification and that the changes are marked as in review.

Never submit unrelated pending changes without explaining them and obtaining approval.

Google Play reviews can take several hours to seven days or longer in exceptional cases. Never promise a specific approval time.

## 8. Visual assets and experiments (separate optimisation workflow)

After the metadata work, recommend visual asset improvements where the audit identified opportunities.

To produce screenshots and the feature graphic (localised, from real app captures), use the `play-store-screenshots` skill: it drives the Script4Me generator `app_store_promo_generator.py` and runs its QA.

### App icon

Google Play requirements:

- 512 × 512 px.
- 32-bit PNG with alpha.
- Maximum 1 MB.

Recommend several genuinely different icon concepts.

### Feature graphic

Mandatory:

- 1024 × 500 px.
- JPEG or 24-bit PNG.
- No transparency.

Check that it communicates the product proposition and complements the rest of the listing.

### Screenshots

Phone listing requirements:

- 2–8 screenshots.
- Minimum dimension 320 px.
- Maximum dimension 3,840 px.

For stronger recommendation-surface eligibility, Google recommends:
- Apps: at least 4 screenshots at 1080 px resolution.
- Games: at least 3 screenshots at 1080 px resolution.

Prioritise real UI and gameplay, a compelling first screenshot and a coherent feature sequence.

Captions are optional and must improve understanding rather than simply repeat search keywords.

### Preview video

Recommend a preview video particularly for games.

- Demonstrate the actual product.
- Communicate the experience immediately.
- Make the video understandable without sound.
- Avoid unnecessary introductory animations.
- Use an eligible public or unlisted YouTube video.
- Ensure that it is embeddable and not age-restricted.
- Disable advertising.

Do not present 30 seconds as the maximum total video duration. Google may autoplay previews for up to 30 seconds depending on placement and device.

### Store Listing Experiments

Use Play Console's Store Listing Experiments to test variations.

Priorities:
1. App icon.
2. First screenshot.
3. Remaining screenshot sequence.
4. Short description.
5. Other listing elements where appropriate.

Rules:

- Test one meaningful variable at a time where possible.
- Avoid superficial variations.
- Ensure sufficient traffic.
- Use the experiment's confidence and data indicators.
- Do not declare a winner when results are inconclusive.
- Record the hypothesis, variant and outcome.

Do not automatically create or launch an experiment without the user's approval.

## 9. Localisation and Custom Store Listings

Audit existing translated listings and identify markets worth prioritising.

Consider:
- Actual target markets.
- Available app languages.
- Existing listing performance.
- Local competitor terminology.
- Translated screenshot text and marketing assets.

Do not assume that every supported UI language requires a translated listing.

For Custom Store Listings, consider:
- Country-specific positioning.
- Search-keyword targeting.
- Campaign-specific messaging.
- Audience-specific assets.

Never create or modify custom listings without including them in the approved scope.

## 10. Post-update and launch monitoring

Recommend monitoring the following through Play Console:

- Store listing impressions.
- Store listing visitors.
- Unique install clicks.
- Install click-through rate.
- Actual acquisitions and first opens.
- Country and language performance.
- Acquisition source and search terms, where available.
- Ratings and reviews.
- Android Vitals.
- User retention and uninstall behaviour.

Distinguish install intent from completed installations.

Check Android Vitals for:
- User-perceived crash rate.
- User-perceived ANR rate.
- Excessive partial wake locks.
- Device-specific stability problems.

Google's current bad-behaviour thresholds include:
- Overall user-perceived crash rate: 1.09%.
- Overall user-perceived ANR rate: 0.47%.
- Per-device crash and ANR rates: 8%.
- Excessive partial wake locks: 5%.

These are warning thresholds, not targets. Aim lower. Verify the latest official thresholds before using fixed values.

Do not claim that a particular number of downloads, install velocity or retention percentage guarantees a ranking improvement.

Recommend Firebase Analytics and Crashlytics when additional product-level measurement would be useful.

## 11. Wrap up

Report clearly:

- What was audited.
- What was changed locally.
- What was saved to Play Console.
- Whether changes are drafts, in review or publicly available.
- Which assets and translations were not touched.
- Outstanding issues and recommendations.

If the project already tracks listing status in `docs/play-store/README.md`, update the relevant status without overwriting unrelated documentation.

Recommend the next highest-impact action based on the actual audit, not a generic checklist.

Maintain old listing files for comparison and rollback.

---

## Official documentation

Use these sources when verifying current Google Play behaviour and requirements:

- https://support.google.com/googleplay/android-developer/
- https://play.google.com/console/
- https://support.google.com/googleplay/android-developer/answer/9859152
- https://support.google.com/googleplay/android-developer/answer/6223646
- https://support.google.com/googleplay/android-developer/answer/9845334
- https://support.google.com/googleplay/android-developer/answer/9845334?hl=en
- https://developer.android.com/google/play/vitals
- https://developer.android.com/guide/playcore/in-app-review
- https://developer.android.com/google/play/requirements/target-sdk

When documentation or policies change, prefer the latest official Google documentation over older recommendations in this skill or its reference files.