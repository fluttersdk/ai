# Flutter Test Generator

Write comprehensive tests for the specified Flutter/Dart code following TDD principles.

## Guidelines

1. Test the **public API contract** — not implementation details
2. Use descriptive test names: `'should [expected behavior] when [condition]'`
3. Group related tests with `group()` blocks
4. Mock dependencies using Mockito or manual mocks
5. Cover edge cases: null inputs, empty collections, error states
6. Widget tests use `pumpWidget` + `find.byType` / `find.text` patterns
7. Follow the testing patterns from `/fluttersdk:magic-framework` skill

## Code to Test

$ARGUMENTS
