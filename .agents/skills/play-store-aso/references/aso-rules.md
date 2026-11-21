
# Google Play ASO Rules

## 1. Core principles

The objective is to maximise relevant discovery and store-listing conversion.

Separate three things:
- Official Google Play requirements and policies.
- Documented Google Play quality and discovery signals.
- ASO hypotheses and marketing best practices.

Google does not publish its complete search-ranking algorithm or keyword-weighting formula.

Never present an undocumented ranking theory as a confirmed Google ranking factor.

Priorities:
1. Relevance to the user's search intent.
2. Clear positioning and differentiation.
3. Strong visual presentation.
4. Accurate expectations and user trust.
5. App quality, engagement and retention.
6. Measurement and continuous experimentation.

## 2. Metadata

| Field | Character limit |
|---|---:|
| App title | 30 |
| Short description | 80 |
| Full description | 4,000 |
| What's New (per language) | 500 |

### App title

- Preserve brand identity where appropriate.
- Include a descriptive category or functionality term when natural.
- Prioritise clarity, uniqueness and relevance.
- Consider brand-first, brand-plus-descriptor and descriptive alternatives.
- Never force keywords or fill the character limit unnecessarily.
- Avoid misleading claims, promotional language and ranking claims.
- Avoid unnecessary emojis, special characters and repeated punctuation.

### Short description

- Communicate the core function and strongest benefit.
- Use natural terminology that describes the product.
- Make the differentiation immediately apparent.
- Avoid duplicating the full description or other promotional assets.
- Do not insert unnecessary keywords for search ranking: Google explicitly states these do not improve ranking.
- Avoid promotional claims and calls to action.
- Keep within 80 characters.

### Full description

- Describe actual functionality, content and differentiating features.
- Make the first few sentences immediately understandable.
- Organise the text into short, readable sections.
- Use bullets where they improve readability.
- Incorporate relevant search terminology naturally.
- Never follow a fixed keyword repetition quota.
- Avoid keyword lists, repetitive synonyms and unrelated references.
- Do not include fabricated content counts, features or endorsements.
- Only reference third-party brands, people and IP when genuinely relevant and appropriately authorised.
- Keep the description accurate as the product evolves.

### What's New

What's New is release information, not a substitute for the main listing.

- Write only when there is a specific release to describe.
- Communicate actual changes and improvements.
- Localise release notes where appropriate.
- Maximum 500 Unicode characters per language.
- No promotional keyword stuffing or requests for user actions.

## 3. Search discovery and keyword research

There is no general-purpose keyword-density field in the standard store listing.

However, Google Play supports Custom Store Listings targeted by search keywords.

Research process:
1. Identify primary and secondary user search intents.
2. Collect relevant search phrases from available ASO research tools.
3. Inspect the apps currently appearing for those searches.
4. Analyse competing titles, positioning, features and visual assets.
5. Identify relevant opportunities where the product has a credible differentiator.
6. Incorporate relevant terminology naturally into the listing.
7. Consider keyword-targeted Custom Store Listings when different search intents justify different messaging.

Do not fabricate keyword search volumes, rankings or difficulty scores.

Do not treat reviews, What's New or arbitrary keyword repetition as confirmed ranking opportunities.

### Custom Store Listings

Google Play supports up to 50 custom listings.

Possible targeting:
- Search keywords.
- Countries and regions.
- Specific audiences.
- Google Ads campaigns.
- Custom listing URLs.

Use separate listings only when the alternative positioning, features or assets are genuinely relevant to the targeted audience.

## 4. Visual assets

Visuals are part of both discovery and conversion.

### App icon
- 512 × 512 px.
- 32-bit PNG with alpha.
- Maximum 1 MB.
- Recognisable at small sizes.
- Distinctive from competing applications.
- Evaluate multiple genuinely different concepts.

### Feature graphic
- Mandatory.
- 1024 × 500 px.
- JPEG or 24-bit PNG, without alpha.
- Communicate the core product proposition.
- Keep important content in the safe central area.
- Complement the icon and product identity.

### Screenshots

Phone requirements:
- 2–8 screenshots.
- 320–3,840 px per side.
- Portrait 9:16 or landscape 16:9.

For recommendation-surface eligibility:
- Apps: at least 4 screenshots at 1080 px resolution.
- Games: at least 3 screenshots at 1080 px resolution.

Optimisation:
- Lead with the strongest representation of the core experience.
- Prioritise actual app/game UI in the first three screenshots.
- Communicate a coherent visual narrative.
- Demonstrate real features and functionality.
- Use promotional text only when it adds meaningful context.
- Keep text minimal and legible.
- Never use captions as a keyword-indexing strategy.
- Localise embedded text for target markets.
- Avoid unsupported claims and misleading representations.

Check alt text for uploaded graphic assets (140 characters or fewer).

### Preview video

Optional, but particularly valuable for games.

- Show the actual experience.
- Communicate the core value immediately.
- Make sense without sound.
- Avoid lengthy logo introductions.
- The video can appear before screenshots and may autoplay muted for up to 30 seconds depending on placement and device.
- Use an eligible public or unlisted YouTube video.
- Disable advertising and ensure the video is embeddable and not age-restricted.
- Localise the video where appropriate.

A weak video is not automatically better than no video.

## 5. Ratings and reviews

- Monitor the public rating and rating volume.
- Analyse negative-review themes.
- Identify recurring usability, quality and expectation issues.
- Respond constructively to feedback.
- Never manipulate ratings or incentivise reviews.
- Never request specific star ratings or keyword-containing reviews.

Use Google Play In-App Review API where appropriate:
- Ask only after users have experienced enough of the app.
- Choose a natural interaction moment.
- Do not ask questions about their opinion before showing the review card.
- Avoid excessive prompts.
- Respect Google's review API quotas.

There is no universal 4.2-star ranking threshold.

## 6. Core value and technical quality

Google evaluates app quality and core value using marketing assets and user metrics.

Relevant signals include:
- Ratings and reviews.
- User engagement and retention.
- Active users.
- Uninstalls and user loss.
- Technical quality and Android Vitals.

Do not claim that a specific install velocity or D1/D7 retention threshold guarantees ranking improvements.

Monitor Android Vitals:
- User-perceived crash rate.
- User-perceived ANR rate.
- Excessive partial wake locks.
- Memory usage.
- Bitmap memory usage.

Current stability bad-behaviour thresholds:
- Overall user-perceived crash rate: 1.09%.
- Overall user-perceived ANR rate: 0.47%.
- Per-phone-model crash and ANR rates: 8%.
- Excessive partial wake locks: 5%.

These are warning thresholds, not performance targets. Aim lower and investigate individual device problems.

Check Google's latest Android Vitals documentation before applying fixed thresholds.

## 7. Localisation

- Prioritise actual target markets, not every locale supported by the app UI.
- Translate title, short description and full description.
- Localise screenshot text, feature graphics and videos.
- Adapt terminology to how users in each market describe the product.
- Inspect existing translated listings for consistency and quality.
- Consider custom store listings where country-specific positioning is justified.

## 8. Store listing experiments

Use Google Play Store Listing Experiments.

Default graphics experiments:
- App icon.
- Feature graphic.
- Screenshots.

Localised experiments:
- Graphics and descriptions in up to five languages.

Best practices:
- Test one asset at a time where possible.
- Prefer genuinely different variants over superficial changes.
- Use Play Console's confidence intervals and minimum detectable effect.
- Ensure enough traffic for meaningful results.
- Do not declare a winner when the result says "More data needed".
- Apply successful variants and document the outcome.

Prioritise icon and screenshot experiments before minor copy changes.

## 9. Measurement and iteration

Monitor:
- Store listing impressions.
- Store listing visitors.
- Unique user install clicks.
- Install click-through rate.
- User acquisitions and first opens.
- Country and language performance.
- Traffic source and search keyword performance.
- Android Vitals.
- Ratings, retention and user loss.

Distinguish install intent from successfully completed installations.

Compare performance before and after changes, accounting for traffic composition and seasonality.

## 10. Continuous improvement

Research → Positioning → Listing → Experiment → Measurement → Iteration.

Prioritise improvements by expected impact and evidence.

Do not change multiple variables simultaneously when running an experiment.

For low-traffic apps, prefer meaningful improvements supported by competitor research and user feedback rather than running inconclusive experiments.

Revisit the listing when:
- The product changes significantly.
- New features alter its positioning.
- New search opportunities emerge.
- Performance data identifies a conversion problem.
- New target markets are introduced.