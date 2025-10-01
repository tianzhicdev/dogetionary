#!/bin/bash

# Claude Code Autonomous TODO Executor
# Implements: implement() -> test() -> eval_result() workflow
# Usage: ./exec_todo.sh [task_number]

set -e

TODO_FILE="todo.txt"
CLAUDE_CMD="claude"
PROJECT_ROOT="/Users/biubiu/projects/dogetionary"
LOG_DIR="$PROJECT_ROOT/todo_logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Create log directory
mkdir -p "$LOG_DIR"

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_step() {
    echo -e "${CYAN}🔧 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    if [ ! -f "$TODO_FILE" ]; then
        print_error "todo.txt not found!"
        echo "Please create a todo.txt file with task definitions."
        exit 1
    fi

    if ! command -v "$CLAUDE_CMD" &> /dev/null; then
        print_error "Claude Code CLI not found!"
        echo "Please install Claude Code CLI and make sure it's in your PATH."
        exit 1
    fi
}

# Parse task from todo.txt
parse_task() {
    local task_num="$1"
    local section=""
    local current_task=""
    local field=""
    local content=""

    while IFS= read -r line; do
        # Skip empty lines and comments starting with #
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Check for task section
        if [[ "$line" =~ ^\[TASK_([0-9]+)\]$ ]]; then
            current_task="${BASH_REMATCH[1]}"
            continue
        fi

        # Check for field definitions
        if [[ "$line" =~ ^([A-Z_]+):[[:space:]]*\|?$ ]]; then
            field="${BASH_REMATCH[1]}"
            content=""
            continue
        fi

        # Collect content for current field
        if [[ -n "$field" && "$current_task" == "$task_num" ]]; then
            if [[ -n "$content" ]]; then
                content="$content\n$line"
            else
                content="$line"
            fi

            # Store the field content
            case "$field" in
                "IMPLEMENT_INSTRUCTION")
                    IMPLEMENT_INSTRUCTION="$content"
                    ;;
                "TEST_INSTRUCTION")
                    TEST_INSTRUCTION="$content"
                    ;;
                "EVAL_CRITERIA")
                    EVAL_CRITERIA="$content"
                    ;;
            esac
        fi

    done < "$TODO_FILE"

    # Check if we found the task
    if [[ -z "$IMPLEMENT_INSTRUCTION" ]]; then
        print_error "Task $task_num not found in todo.txt"
        return 1
    fi

    return 0
}

# Function 1: implement(todo_item) -> implementation log
implement() {
    local task_num="$1"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local impl_log="$LOG_DIR/task_${task_num}_implement_${timestamp}.log"

    print_step "IMPLEMENT: Executing task $task_num with Claude Code"
    print_info "Implementation log: $impl_log"

    echo "=== IMPLEMENTATION PHASE ===" > "$impl_log"
    echo "Task: $task_num" >> "$impl_log"
    echo "Timestamp: $(date)" >> "$impl_log"
    echo "Instruction:" >> "$impl_log"
    echo -e "$IMPLEMENT_INSTRUCTION" >> "$impl_log"
    echo "===========================" >> "$impl_log"
    echo "" >> "$impl_log"

    # Execute with Claude Code
    local claude_prompt="TASK: Implement the following requirement autonomously.

$IMPLEMENT_INSTRUCTION

IMPORTANT:
- Execute this task completely and thoroughly
- Make all necessary file changes
- Test your changes as you go
- Provide detailed output of what you accomplished
- Do not ask for confirmation - proceed with implementation
- Report any issues or blockers you encounter"

    print_info "Sending implementation instruction to Claude Code..."

    if echo "$claude_prompt" | $CLAUDE_CMD --dangerously-skip-permissions 2>&1 | tee -a "$impl_log"; then
        echo "" >> "$impl_log"
        echo "Implementation completed at: $(date)" >> "$impl_log"
        print_success "Implementation phase completed"
        echo "$impl_log"
        return 0
    else
        echo "Implementation failed at: $(date)" >> "$impl_log"
        print_error "Implementation phase failed"
        echo "$impl_log"
        return 1
    fi
}

# Function 2: test(implementation_log, test_instructions) -> result
test() {
    local task_num="$1"
    local impl_log="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local test_log="$LOG_DIR/task_${task_num}_test_${timestamp}.log"

    print_step "TEST: Validating implementation with Claude Code"
    print_info "Test log: $test_log"

    echo "=== TESTING PHASE ===" > "$test_log"
    echo "Task: $task_num" >> "$test_log"
    echo "Timestamp: $(date)" >> "$test_log"
    echo "Implementation log: $impl_log" >> "$test_log"
    echo "Test instruction:" >> "$test_log"
    echo -e "$TEST_INSTRUCTION" >> "$test_log"
    echo "===================" >> "$test_log"
    echo "" >> "$test_log"

    # Get implementation summary
    local impl_summary=""
    if [[ -f "$impl_log" ]]; then
        impl_summary=$(tail -50 "$impl_log")
    fi

    # Execute testing with Claude Code
    local claude_test_prompt="TASK: Test and validate the implementation that was just completed.

IMPLEMENTATION SUMMARY:
$impl_summary

TEST INSTRUCTIONS:
$TEST_INSTRUCTION

REQUIREMENTS:
- Execute all specified tests thoroughly
- Check that the implementation meets the requirements
- Verify functionality is working correctly
- Test edge cases and error conditions
- Provide detailed test results
- Report PASS/FAIL for each test category
- Do not ask for confirmation - proceed with testing
- Be thorough and comprehensive in your testing"

    print_info "Sending test instruction to Claude Code..."

    if echo "$claude_test_prompt" | $CLAUDE_CMD --dangerously-skip-permissions 2>&1 | tee -a "$test_log"; then
        echo "" >> "$test_log"
        echo "Testing completed at: $(date)" >> "$test_log"
        print_success "Testing phase completed"
        echo "$test_log"
        return 0
    else
        echo "Testing failed at: $(date)" >> "$test_log"
        print_error "Testing phase failed"
        echo "$test_log"
        return 1
    fi
}

# Function 3: eval_result() -> boolean
eval_result() {
    local task_num="$1"
    local test_log="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local eval_log="$LOG_DIR/task_${task_num}_eval_${timestamp}.log"

    print_step "EVAL: Evaluating test results with Claude Code"
    print_info "Evaluation log: $eval_log"

    echo "=== EVALUATION PHASE ===" > "$eval_log"
    echo "Task: $task_num" >> "$eval_log"
    echo "Timestamp: $(date)" >> "$eval_log"
    echo "Test log: $test_log" >> "$eval_log"
    echo "Evaluation criteria:" >> "$eval_log"
    echo -e "$EVAL_CRITERIA" >> "$eval_log"
    echo "=====================" >> "$eval_log"
    echo "" >> "$eval_log"

    # Get test results summary
    local test_summary=""
    if [[ -f "$test_log" ]]; then
        test_summary=$(tail -100 "$test_log")
    fi

    # Execute evaluation with Claude Code
    local claude_eval_prompt="TASK: Evaluate whether the implementation and testing results meet the success criteria.

TEST RESULTS SUMMARY:
$test_summary

EVALUATION CRITERIA:
$EVAL_CRITERIA

INSTRUCTIONS:
- Carefully review all test results
- Check each criteria against the evidence
- Be strict in your evaluation - all criteria must be met
- Respond with EXACTLY ONE of these formats:
  - If successful: 'EVALUATION: TRUE - [brief reason]'
  - If failed: 'EVALUATION: FALSE - [specific issues that need to be addressed]'
- Do not provide any other response format
- Base your decision solely on objective evidence from the test results"

    print_info "Sending evaluation request to Claude Code..."

    local eval_response
    eval_response=$(echo "$claude_eval_prompt" | $CLAUDE_CMD --dangerously-skip-permissions 2>&1)

    echo "$eval_response" >> "$eval_log"
    echo "Evaluation completed at: $(date)" >> "$eval_log"

    # Parse the response
    if echo "$eval_response" | grep -q "EVALUATION: TRUE"; then
        local reason=$(echo "$eval_response" | grep "EVALUATION: TRUE" | sed 's/EVALUATION: TRUE - //')
        print_success "Evaluation PASSED: $reason"
        echo "RESULT: TRUE" >> "$eval_log"
        return 0
    elif echo "$eval_response" | grep -q "EVALUATION: FALSE"; then
        local issues=$(echo "$eval_response" | grep "EVALUATION: FALSE" | sed 's/EVALUATION: FALSE - //')
        print_error "Evaluation FAILED: $issues"
        echo "RESULT: FALSE" >> "$eval_log"
        return 1
    else
        print_error "Evaluation response was malformed: $eval_response"
        echo "RESULT: ERROR - Malformed response" >> "$eval_log"
        return 1
    fi
}

# Execute a complete task cycle
execute_task_cycle() {
    local task_num="$1"
    local max_attempts=3
    local attempt=1

    print_header "EXECUTING TASK $task_num"

    # Parse task from todo.txt
    if ! parse_task "$task_num"; then
        return 1
    fi

    print_info "Task loaded successfully"
    print_info "Implement instruction: $(echo -e "$IMPLEMENT_INSTRUCTION" | head -1)..."

    while [ $attempt -le $max_attempts ]; do
        print_info "Attempt $attempt/$max_attempts"

        # Phase 1: Implement
        local impl_log
        if impl_log=$(implement "$task_num"); then
            print_success "Implementation successful"

            # Phase 2: Test
            local test_log
            if test_log=$(test "$task_num" "$impl_log"); then
                print_success "Testing successful"

                # Phase 3: Evaluate
                if eval_result "$task_num" "$test_log"; then
                    print_success "Task $task_num completed successfully!"
                    return 0
                else
                    print_warning "Evaluation failed on attempt $attempt"
                fi
            else
                print_error "Testing failed on attempt $attempt"
            fi
        else
            print_error "Implementation failed on attempt $attempt"
        fi

        ((attempt++))
        if [ $attempt -le $max_attempts ]; then
            print_warning "Retrying in 5 seconds..."
            sleep 5
        fi
    done

    print_error "Task $task_num failed after $max_attempts attempts"
    return 1
}

# Get list of available tasks
get_available_tasks() {
    grep -oE "\[TASK_([0-9]+)\]" "$TODO_FILE" | grep -oE "[0-9]+" | sort -n
}

# Main execution logic
main() {
    cd "$PROJECT_ROOT"
    check_prerequisites

    local target_task="$1"
    local available_tasks
    available_tasks=($(get_available_tasks))

    if [ ${#available_tasks[@]} -eq 0 ]; then
        print_error "No tasks found in todo.txt"
        exit 1
    fi

    print_header "CLAUDE CODE AUTONOMOUS EXECUTOR"
    print_info "Available tasks: ${available_tasks[*]}"
    echo ""

    if [ -n "$target_task" ]; then
        # Execute single task
        if [[ " ${available_tasks[*]} " =~ " $target_task " ]]; then
            execute_task_cycle "$target_task"
        else
            print_error "Task $target_task not found"
            print_info "Available tasks: ${available_tasks[*]}"
            exit 1
        fi
    else
        # Execute all tasks in sequence
        local failed_tasks=()

        for task_num in "${available_tasks[@]}"; do
            if ! execute_task_cycle "$task_num"; then
                failed_tasks+=("$task_num")
                print_error "Stopping execution due to task $task_num failure"
                break
            fi
            echo ""
        done

        # Report final results
        if [ ${#failed_tasks[@]} -eq 0 ]; then
            print_success "All tasks completed successfully!"
        else
            print_error "Execution stopped. Failed tasks: ${failed_tasks[*]}"
            exit 1
        fi
    fi
}

# Show usage if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Claude Code Autonomous TODO Executor"
    echo "Usage: $0 [task_number]"
    echo ""
    echo "Options:"
    echo "  task_number    Execute only the specified task (optional)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "How it works:"
    echo "  1. implement() - Claude Code executes the implementation"
    echo "  2. test() - Claude Code validates the implementation"
    echo "  3. eval_result() - Claude Code evaluates if criteria are met"
    echo ""
    echo "Only tasks that pass all phases will be considered complete."
    echo "If no task_number is provided, all tasks will be executed in sequence."
    exit 0
fi

# Run main function
main "$@"