//
//  ALPHAEQT_CHECKLIST.MD
//  AlphaEqt
//
//  Created by Alpha Ng on 27/9/2025.
//
# AlphaEqt Project Checklist

## 1. Library Core Development

- [x] Create GitHub repository: AlphaEqt
- [x] Set up initial folder structure:
    - Sources/AlphaEqt/Lexer/
    - Sources/AlphaEqt/Parser/
    - Sources/AlphaEqt/Render/
    - Sources/AlphaEqt/MathView/
    - Sources/AlphaEqt/Core/
    - Tests/AlphaEqtTests/
    - Demo/DemoApp/
- [x] Add README and LICENSE
- [ ] Add Package.swift and initialize as a Swift package
- [ ] Scaffold basic files for each module (`Lexer.swift`, `Parser.swift`, etc.)
- [ ] Implement Lexer (tokenizer for math input)
- [ ] Implement Parser (AST builder)
- [ ] Define AST node types (protocols/classes)
- [ ] Implement Renderer/Layout engine
- [ ] Implement MathView (SwiftUI/UIView integration)
- [ ] Write unit tests for each module
- [ ] Document code and architecture (README, inline docs)

## 2. App Development

- [ ] Create demo app in Demo/DemoApp/
- [ ] Integrate AlphaEqt library into app
- [ ] Design UI for math input and rendering
- [ ] Add sample equations and interactive features
- [ ] Write UI and integration tests
- [ ] Prepare for App Store submission (app metadata, icons, privacy, etc.)

## 3. Publishing & Distribution

- [ ] Publish AlphaEqt as a Swift package (public repo, documentation)
- [ ] Release app on App Store
- [ ] Write usage guides/tutorials
- [ ] Announce release (GitHub, forums, social media, etc.)

## 4. Cross-Platform Planning

- [ ] Evaluate architecture for Android/cross-platform port
- [ ] Document core logic for portability (no Apple-specific dependencies in core)
- [ ] Explore approaches (Kotlin Multiplatform, C++ core, Rust core, etc.)
- [ ] Set up future roadmap for Android version

## 5. Quality & Collaboration

- [ ] Set up CI/CD (GitHub Actions, unit tests on push/PR)
- [ ] Choose and document project license (MIT recommended)
- [ ] Add contributing guidelines
- [ ] Invite contributors and collaborators

---

**Tip:**
Check off each item as you progress.
Update this checklist to track new ideas, issues, and milestones!
