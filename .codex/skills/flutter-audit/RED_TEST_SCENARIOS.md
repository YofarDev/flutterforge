# RED Phase Test Scenarios: flutter-audit

## Purpose
Document baseline behavior WITHOUT the skill to prove it addresses real problems.

## Pressure Scenario 1: Generic "Review My Code"
**Task:** "Can you review my Flutter project? I want to know if the architecture is good."

**Expected baseline failures (without skill):**
- May read random files without systematic approach
- May give generic feedback ("looks good")
- May not check for specific anti-patterns
- May not prioritize issues by severity
- May not produce actionable report with file paths

## Pressure Scenario 2: Specific Concern
**Task:** "I think my BLoC structure might be wrong. Can you check?"

**Expected baseline failures:**
- May only look at BLoC files, not architecture holistically
- May not verify BLoC vs Cubit justification
- May not check state exhaustiveness
- May not identify layer boundary violations
- May not provide prioritized findings

## Pressure Scenario 3: Time Pressure - Large Codebase
**Context:** "We need an architecture review before our sprint demo tomorrow. The project has 20 features."

**Expected baseline failures:**
- May manually grep for patterns (inefficient)
- May skip systematic checks
- May get overwhelmed and give superficial review
- May not use automation scripts
- May not structure findings by severity

## Pressure Scenario 4: "What's Wrong?" Request
**Task:** Users asks "What's wrong with my architecture?" after sharing several files

**Expected baseline failures:**
- May complain about missing context instead of analyzing
- May give laundry list without prioritization
- May not format findings as actionable report
- May not distinguish critical vs cosmetic issues
- May not offer to fix issues found

## Pressure Scenario 5: Maintenance Burden Concern
**Task:** "Our app is getting hard to maintain. Can you identify why?"

**Expected baseline failures:**
- May not check file size violations
- May not identify cross-feature imports
- May not find nested BlocListeners
- May not detect widget helper methods
- May not check for DI violations
- May not quantify the problems

## Success Criteria (WITH skill)
Agent should:
1. Run systematic analysis (fanal script if available)
2. Check specific categories: structure, state, errors, DI, routing, models, standards
3. Prioritize findings by severity (Critical/Warning/Suggestion)
4. Provide specific file paths and line numbers for each issue
5. Format as structured report with clear fix recommendations
6. Offer to implement fixes after report
7. Focus on architecture violations, not style
