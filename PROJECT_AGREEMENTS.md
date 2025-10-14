# SilverSupport Development Document

## Project Overview

**Project Name:** SilverSupport

**Purpose:** Phone answering AI-powered technical support service for seniors

**Description:** 
SilverSupport provides technical assistance to seniors who call in with technical issues. The system:
- Receives calls through Twilio API
- Listens to caller questions
- Searches a database containing questions, answers, and categories
- Uses OpenAI and Claude AI to enhance responses
- Provides patient, step-by-step resolutions to technical problems

---

## Current Development Focus

**Installer Script for Ubuntu Linux**

The installer script is designed to:
- Run on a clean Ubuntu Linux server
- Deploy all SilverSupport code to correct server locations
- Install all required software modules and dependencies
- Retrieve code from S3 bucket (tarball format)
- Retrieve installer itself from separate S3 bucket

---

## Technology Stack

- **Frontend:** React
- **Backend:** Node.js
- **Language:** JavaScript
- **Phone Integration:** Twilio API
- **Database:** [To be specified]
- **AI Services:** OpenAI, Claude (Anthropic)
- **Deployment:** Ubuntu Linux Server
- **Storage:** AWS S3 (for code distribution)

---

## Development Philosophy

### Modular Architecture
- **CRITICAL:** All code must be modular
- Changes in one module must not disrupt other modules
- Each module should be independently testable and maintainable

### Documentation Standards
- Create markdown documentation for each module/area
- All documentation stored in GitHub repository
- Documentation should be created after each module is completed
- Clear, concise technical documentation preferred

### Testing Approach
- Test as development progresses (incremental testing)
- Use unit tests for code sections
- Testing should validate module independence

---

## Communication & Workflow Agreements

### Code Generation Process
1. User describes desired feature or bug fix
2. Claude generates the code
3. Claude explains what the code does
4. User validates if it matches their vision
5. Iterate if needed

### Response Style Preferences
- **Default:** Concise explanations with code snippets
- **When Requested:** Full code files
- **Skip:** Super basic concept explanations (user is technically competent)
- **Remember:** User knows what they want code to produce, but depends on Claude for implementation

### Code Update Format
**Preferred style:** "Find this code and replace it with this code"

Example:
```
Find:
[old code snippet]

Replace with:
[new code snippet]
```

**Alternative:** When requested, provide complete file replacement

### User's Development Environment
- **Linux:** VI editor
- **Mac:** VSCode editor
- User is comfortable with command-line operations

---

## What Claude Should Always Do

1. Generate working, modular code
2. Explain what the code does and how it works
3. Provide code in requested format (snippet or full file)
4. Use clear "find and replace" format for edits
5. Create markdown documentation after module completion
6. Consider module independence in all solutions
7. Test code logic before presenting

---

## What Claude Should Avoid

1. Over-explaining basic concepts
2. Assuming user needs to learn the code
3. Breaking modularity with cross-module dependencies
4. Verbose explanations when concise ones suffice
5. Suggesting nano when VI is preferred

---

## Project Goals & Success Criteria

The installer must:
- Successfully deploy on clean Ubuntu Linux server
- Install all required dependencies automatically
- Retrieve code from S3 buckets
- Place all files in correct server locations
- Be maintainable and modular
- Handle errors gracefully

---

## Notes

- User is familiar with how code works conceptually
- User validates output against their vision
- Focus is on producing working code, not teaching programming
- Patient, step-by-step approach aligns with SilverSupport's mission for seniors

---

## Document Version
**Created:** October 14, 2025  
**Last Updated:** October 14, 2025

---

*This document should be referenced at the start of each new conversation to ensure consistency and alignment with project goals.*
