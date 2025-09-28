# Automated TODO Execution System

This system allows you to define development tasks and testing criteria, then execute them automatically using Claude Code CLI.

## Files

- **`exec_todo.sh`** - Main execution script
- **`todo.txt`** - Task definitions and testing criteria
- **`todo_logs/`** - Generated log files for each execution

## Usage

### Execute All Tasks
```bash
./exec_todo.sh
```

### Execute Specific Task
```bash
./exec_todo.sh 1    # Execute only task 1
./exec_todo.sh 3    # Execute only task 3
```

### Get Help
```bash
./exec_todo.sh --help
```

## Todo File Format

The `todo.txt` file uses a simple section-based format:

### [TASKS] Section
List numbered tasks that will be executed by Claude Code:

```
[TASKS]
1. Remove unused imports in iOS Swift files
2. Add error handling for network failures
3. Update documentation
```

### [TESTING] Section
List shell commands to validate the changes:

```
[TESTING]
# Compile iOS app
cd ios && xcodebuild -project MyApp.xcodeproj build
# Run backend tests
cd src && python -m pytest tests/
# Check service health
curl -f http://localhost:5000/health
```

## Features

- **🎯 Selective Execution**: Run specific tasks by number
- **📝 Comprehensive Logging**: Each task execution is logged with timestamps
- **🧪 Automated Testing**: Run validation tests after task completion
- **🎨 Colored Output**: Easy-to-read console output with status indicators
- **⚡ Claude Integration**: Uses Claude Code CLI with full permissions
- **🛡️ Error Handling**: Stops on failures and reports status

## Example Output

```bash
$ ./exec_todo.sh 1
================================
  TODO EXECUTOR - EXECUTING TASK 1
================================
ℹ️  Task: Remove unused imports in iOS Swift files
ℹ️  Log: /path/to/todo_logs/task_1_20241225_143022.log
✅ Task 1 completed successfully

================================
  TODO EXECUTOR - RUNNING TESTS
================================
ℹ️  Running: cd ios && xcodebuild -project MyApp.xcodeproj build
✅ Test passed: cd ios && xcodebuild -project MyApp.xcodeproj build
✅ All tests passed!
```

## Requirements

- Claude Code CLI installed and in PATH
- Project dependencies set up
- Appropriate permissions for Claude Code operations

## Best Practices

1. **Keep tasks atomic** - Each task should be a single, well-defined change
2. **Add comprehensive tests** - Include compilation, unit tests, and integration tests
3. **Use descriptive task names** - Make it clear what each task accomplishes
4. **Review logs** - Check the generated logs for detailed execution information
5. **Test iteratively** - Run individual tasks during development, full suite before commits

## Troubleshooting

- **Task fails**: Check the log file in `todo_logs/` for detailed error information
- **Tests fail**: Ensure your testing commands work independently before adding them
- **Claude not found**: Make sure Claude Code CLI is installed and in your PATH
- **Permission issues**: The script uses `--dangerously-skip-permissions` for automation