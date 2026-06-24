# CurationLab

CurationLab is an iOS application designed to curate event-based photo albums using Large Language Models (LLMs) and advanced visual analysis.

## Features

- **Event Clustering**: Group photo library assets into events automatically.
- **LLM Curation**: Use LLMs to curate the best photos from a group and generate memories, stories, and headlines.
- **Vision Integration**: Tag and analyze images using on-device vision APIs.
- **Custom Prompts & Slideshows**: Customize prompt engineering and run slideshow views for curated tags.

## Development Setup

The Xcode project is generated using [XcodeGen](https://github.com/yonaskolb/XcodeGen). Do not commit `.xcodeproj` changes directly.

### Prerequisites

Make sure XcodeGen is installed:
```bash
brew install xcodegen
```

### Generating the Project

To generate the `.xcodeproj` file from the configuration, run:
```bash
xcodegen generate
```

## Testing Suite

A unit testing suite is configured to verify model serialization, LLM parser configurations, and custom settings logic.

### Running Tests

To run the unit tests via the Xcode GUI:
- Open `CurationLab.xcodeproj`.
- Press `Cmd + U` or select **Product > Test** from the menu.

To run the unit tests via the Command Line Interface (CLI):
```bash
xcodebuild -project CurationLab.xcodeproj -scheme CurationLab -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Commit & Regression Prevention Policy

> [!IMPORTANT]
> **All unit tests must pass before code is committed to the repository.**
> This project enforces a zero-regression policy. If you make changes to models, services, or parser logic, run the test suite and ensure all tests are green before pushing or requesting reviews.
