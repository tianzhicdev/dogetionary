# Claude Code Autonomous TODO Execution System

This system implements a fully autonomous task execution workflow using Claude Code with no human intervention required.

## Architecture

The system follows a three-function pipeline:

1. **`implement(todo_item)`** → Implementation log
2. **`test(implementation_log, test_instructions)`** → Test results
3. **`eval_result(test_results, criteria)`** → Boolean (true/false)

Only when `eval_result()` returns `true` does the system move to the next task.

## File Structure

### `todo.txt` - Task Definitions
Each task is defined with three instruction blocks:

```
[TASK_N]
IMPLEMENT_INSTRUCTION: |
  Detailed instructions for Claude Code to implement the feature
  - What to build
  - How to structure it
  - Requirements and constraints

TEST_INSTRUCTION: |
  Detailed instructions for Claude Code to test the implementation
  - What to verify
  - How to test it
  - Expected behaviors

EVAL_CRITERIA: |
  Strict criteria for evaluating success
  - All conditions that must be met
  - Pass/fail requirements
```

### `exec_todo.sh` - Autonomous Executor
The shell script orchestrates the three-phase execution:

- **Phase 1 (Implement)**: Sends implementation instructions to Claude Code
- **Phase 2 (Test)**: Sends test instructions with implementation context
- **Phase 3 (Evaluate)**: Sends evaluation criteria with test results

## Usage

```bash
# Execute all tasks autonomously
./exec_todo.sh

# Execute specific task
./exec_todo.sh 1

# Show help
./exec_todo.sh --help
```

## Workflow

For each task:

1. **Parse Task**: Extract instructions from `todo.txt`
2. **Implement**: Claude Code receives implementation instructions and executes
3. **Test**: Claude Code receives test instructions and validates implementation
4. **Evaluate**: Claude Code reviews test results against strict criteria
5. **Decision**: Only proceed if evaluation returns `TRUE`
6. **Retry**: Up to 3 attempts per task with failure context

## Key Features

### Autonomous Execution
- No human intervention required
- Claude Code makes all implementation decisions
- Automatic retry with failure context
- Strict evaluation criteria prevent false positives

### Comprehensive Logging
```
todo_logs/
├── task_1_implement_TIMESTAMP.log    # Implementation details
├── task_1_test_TIMESTAMP.log         # Test execution results
└── task_1_eval_TIMESTAMP.log         # Evaluation decision
```

### Instruction-Based Testing
Instead of static commands, Claude Code receives dynamic instructions:
- "Test that the backend starts without errors"
- "Verify all endpoints respond correctly"
- "Check that code organization follows patterns"

### Strict Evaluation
Claude Code must respond with exact format:
- `EVALUATION: TRUE - [reason]`
- `EVALUATION: FALSE - [specific issues]`

## Example Task Definition

```
[TASK_1]
IMPLEMENT_INSTRUCTION: |
  Reorganize app_refactored.py by moving functions to appropriate handler files.

  GOALS:
  - Move daily test vocabulary functions to handlers/test_vocabulary.py
  - Move logging setup to middleware/logging.py
  - Keep only route registrations and main app setup in app_refactored.py

  REQUIREMENTS:
  - Create new files following existing project structure
  - Update all import statements
  - Maintain backward compatibility

TEST_INSTRUCTION: |
  Verify the reorganization was successful:

  1. Backend starts without errors
  2. All endpoints respond correctly
  3. Integration tests pass
  4. iOS compilation works
  5. Code organization is improved

EVAL_CRITERIA: |
  Return TRUE only if ALL conditions are met:
  1. app_refactored.py is significantly smaller
  2. Functions moved to logical files
  3. All imports working correctly
  4. Backend starts and responds
  5. Integration tests pass
  6. iOS compilation succeeds
  7. No functionality broken
```

## Benefits

1. **Zero Human Intervention**: Tasks execute completely autonomously
2. **Reliable Validation**: Strict testing and evaluation phases
3. **Failure Recovery**: Automatic retry with context from previous attempts
4. **Comprehensive Logging**: Full audit trail of all decisions and actions
5. **Flexible Instructions**: Claude Code adapts to dynamic requirements rather than static commands

This system enables truly autonomous software development where Claude Code can execute complex multi-step tasks with confidence that all requirements are met before proceeding.