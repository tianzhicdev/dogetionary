#!/bin/bash

# Automated TODO executor with Claude Code
# Usage: ./exec_todo.sh [task_number]

set -e  # Exit on any error

TODO_FILE="todo.txt"
CLAUDE_CMD="claude"
PROJECT_ROOT="/Users/biubiu/projects/dogetionary"
LOG_DIR="$PROJECT_ROOT/todo_logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create log directory
mkdir -p "$LOG_DIR"

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  TODO EXECUTOR - $1${NC}"
    echo -e "${BLUE}================================${NC}"
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

# Check if todo.txt exists
if [ ! -f "$TODO_FILE" ]; then
    print_error "todo.txt not found!"
    echo "Please create a todo.txt file with tasks and testing criteria."
    exit 1
fi

# Check if Claude Code is available
if ! command -v "$CLAUDE_CMD" &> /dev/null; then
    print_error "Claude Code CLI not found!"
    echo "Please install Claude Code CLI and make sure it's in your PATH."
    exit 1
fi

# Parse todo.txt and extract tasks
parse_todo_file() {
    local section=""
    local task_num=0

    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        # Check for section headers
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            section="${line//[\[\]]/}"
            continue
        fi

        # Parse tasks
        if [[ "$section" == "TASKS" && "$line" =~ ^[0-9]+\. ]]; then
            ((task_num++))
            echo "TASK_${task_num}|${line#*. }"
        elif [[ "$section" == "TESTING" ]]; then
            echo "TESTING|$line"
        fi
    done < "$TODO_FILE"
}

# Execute comprehensive testing for a task
run_comprehensive_tests() {
    local task_num="$1"
    local attempt="$2"
    local test_log="$3"

    print_info "Running comprehensive tests (attempt $attempt)..."
    echo "=== COMPREHENSIVE TESTING (Attempt $attempt) ===" >> "$test_log"

    local test_failed=0
    local test_results=()

    # Backend health check
    print_info "Testing backend health..."
    if curl -f http://localhost:5000/health >/dev/null 2>&1; then
        print_success "✅ Backend health check passed"
        test_results+=("PASS: Backend health check")
        echo "PASS: Backend health check" >> "$test_log"
    else
        print_error "❌ Backend health check failed"
        test_results+=("FAIL: Backend health check")
        echo "FAIL: Backend health check" >> "$test_log"
        test_failed=1
    fi

    # Database connection test
    print_info "Testing database connection..."
    if docker exec dogetionary-postgres-1 psql -U dogeuser -d dogetionary -c "SELECT 1;" >/dev/null 2>&1; then
        print_success "✅ Database connection passed"
        test_results+=("PASS: Database connection")
        echo "PASS: Database connection" >> "$test_log"
    else
        print_error "❌ Database connection failed"
        test_results+=("FAIL: Database connection")
        echo "FAIL: Database connection" >> "$test_log"
        test_failed=1
    fi

    # Run integration tests
    print_info "Running integration tests..."
    if python src/tests/test_integration_comprehensive.py >/dev/null 2>&1; then
        print_success "✅ Integration tests passed"
        test_results+=("PASS: Integration tests")
        echo "PASS: Integration tests" >> "$test_log"
    else
        print_error "❌ Integration tests failed"
        test_results+=("FAIL: Integration tests")
        echo "FAIL: Integration tests" >> "$test_log"
        test_failed=1
    fi

    # iOS compilation test
    print_info "Testing iOS compilation..."
    if cd ios/dogetionary && xcodebuild -project dogetionary.xcodeproj -scheme dogetionary -destination 'platform=iOS Simulator,name=iPhone 16' build >/dev/null 2>&1; then
        print_success "✅ iOS compilation passed"
        test_results+=("PASS: iOS compilation")
        echo "PASS: iOS compilation" >> "$test_log"
        cd - >/dev/null
    else
        print_error "❌ iOS compilation failed"
        test_results+=("FAIL: iOS compilation")
        echo "FAIL: iOS compilation" >> "$test_log"
        cd - >/dev/null
        test_failed=1
    fi

    # Docker services status
    print_info "Checking Docker services..."
    if docker-compose ps | grep -E "(Up|healthy)" >/dev/null 2>&1; then
        print_success "✅ Docker services running"
        test_results+=("PASS: Docker services")
        echo "PASS: Docker services" >> "$test_log"
    else
        print_error "❌ Docker services not healthy"
        test_results+=("FAIL: Docker services")
        echo "FAIL: Docker services" >> "$test_log"
        test_failed=1
    fi

    # Log summary
    echo "=== TEST RESULTS SUMMARY ===" >> "$test_log"
    for result in "${test_results[@]}"; do
        echo "$result" >> "$test_log"
    done
    echo "Overall: $([[ $test_failed -eq 0 ]] && echo "PASS" || echo "FAIL")" >> "$test_log"
    echo "============================" >> "$test_log"

    return $test_failed
}

# Execute a single task with iterative testing and Claude Code evaluation
execute_task() {
    local task_num="$1"
    local task_description="$2"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local log_file="$LOG_DIR/task_${task_num}_${timestamp}.log"
    local test_log="$LOG_DIR/task_${task_num}_tests_${timestamp}.log"
    local max_attempts=3
    local attempt=1

    print_header "EXECUTING TASK $task_num"
    print_info "Task: $task_description"
    print_info "Log: $log_file"
    print_info "Test Log: $test_log"

    echo "Starting task execution at $(date)" > "$log_file"
    echo "Task: $task_description" >> "$log_file"
    echo "Max attempts: $max_attempts" >> "$log_file"
    echo "================================" >> "$log_file"

    while [ $attempt -le $max_attempts ]; do
        print_info "Attempt $attempt/$max_attempts"
        echo "=== ATTEMPT $attempt ===" >> "$log_file"

        # Execute with Claude Code
        local claude_cmd="$task_description"
        if [ $attempt -gt 1 ]; then
            # For subsequent attempts, include context about previous failures
            claude_cmd="$task_description

Previous attempt failed. Please review the test logs and fix any issues found:
$(cat "$test_log" 2>/dev/null | tail -20)

Please ensure all tests pass before considering the task complete."
        fi

        print_info "Executing with Claude Code..."
        if $CLAUDE_CMD --dangerously-skip-permissions "$claude_cmd" 2>&1 | tee -a "$log_file"; then
            echo "Claude Code execution completed at $(date)" >> "$log_file"

            # Run comprehensive tests
            echo "=== TESTING PHASE ===" >> "$log_file"
            if run_comprehensive_tests "$task_num" "$attempt" "$test_log"; then
                print_success "Task $task_num completed successfully with all tests passing!"
                echo "Task completed successfully with all tests passing at $(date)" >> "$log_file"

                # Use Claude Code to evaluate and confirm success
                print_info "Getting Claude Code evaluation of success..."
                local evaluation_prompt="Please review the test results and confirm that task '$task_description' has been completed successfully.

Test log summary:
$(tail -20 "$test_log" 2>/dev/null)

Respond with 'SUCCESS' if all tests are passing and the task is truly complete, or 'NEEDS_WORK' with specific issues if more work is needed."

                local claude_evaluation
                claude_evaluation=$($CLAUDE_CMD --dangerously-skip-permissions "$evaluation_prompt" 2>/dev/null | head -1)
                echo "Claude evaluation: $claude_evaluation" >> "$log_file"

                if [[ "$claude_evaluation" == *"SUCCESS"* ]]; then
                    print_success "Claude Code confirms task completion!"
                    return 0
                else
                    print_warning "Claude Code suggests more work needed: $claude_evaluation"
                    echo "Claude suggests more work needed: $claude_evaluation" >> "$log_file"
                fi
            else
                print_error "Tests failed on attempt $attempt"
                echo "Tests failed on attempt $attempt at $(date)" >> "$log_file"
            fi
        else
            print_error "Claude Code execution failed on attempt $attempt"
            echo "Claude Code execution failed on attempt $attempt at $(date)" >> "$log_file"
        fi

        ((attempt++))
        if [ $attempt -le $max_attempts ]; then
            print_warning "Retrying in 5 seconds..."
            sleep 5
        fi
    done

    print_error "Task $task_num failed after $max_attempts attempts"
    echo "Task failed after $max_attempts attempts at $(date)" >> "$log_file"

    # Final evaluation with Claude Code for failure analysis
    print_info "Getting failure analysis from Claude Code..."
    local failure_analysis_prompt="Task '$task_description' failed after $max_attempts attempts. Please analyze the logs and provide recommendations for manual intervention:

Test failures:
$(tail -30 "$test_log" 2>/dev/null)

Execution log:
$(tail -30 "$log_file" 2>/dev/null)"

    $CLAUDE_CMD --dangerously-skip-permissions "$failure_analysis_prompt" 2>&1 | tee -a "$log_file"

    return 1
}

# Execute final validation tests (simplified, since comprehensive tests are run per task)
run_final_validation() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local test_log="$LOG_DIR/final_validation_${timestamp}.log"

    print_header "FINAL VALIDATION"
    print_info "Running final system validation..."
    print_info "Test log: $test_log"

    echo "Starting final validation at $(date)" > "$test_log"
    echo "================================" >> "$test_log"

    # Run one final comprehensive test to ensure everything still works
    if run_comprehensive_tests "FINAL" "1" "$test_log"; then
        print_success "Final validation passed!"
        echo "Final validation passed at $(date)" >> "$test_log"

        # Get Claude Code final assessment
        print_info "Getting Claude Code final assessment..."
        local final_assessment_prompt="Please provide a final assessment of the project state after all tasks have been completed.

Review the system health:
$(tail -20 "$test_log" 2>/dev/null)

Confirm if the project is in a good state and all critical functionality is working."

        $CLAUDE_CMD --dangerously-skip-permissions "$final_assessment_prompt" 2>&1 | tee -a "$test_log"
        return 0
    else
        print_error "Final validation failed!"
        echo "Final validation failed at $(date)" >> "$test_log"

        # Get Claude Code failure analysis
        print_error "Getting failure analysis from Claude Code..."
        local final_failure_prompt="Final validation failed after completing all tasks. Please analyze what went wrong and provide recommendations:

Test failures:
$(tail -30 "$test_log" 2>/dev/null)"

        $CLAUDE_CMD --dangerously-skip-permissions "$final_failure_prompt" 2>&1 | tee -a "$test_log"
        return 1
    fi
}

# Main execution logic
main() {
    cd "$PROJECT_ROOT"

    # Parse command line arguments
    local target_task="$1"

    # Parse todo file
    local -a tasks=()
    local -a task_descriptions=()

    while IFS='|' read -r type content; do
        if [[ "$type" =~ ^TASK_[0-9]+$ ]]; then
            local task_num="${type#TASK_}"
            tasks+=("$task_num")
            task_descriptions+=("$content")
        fi
    done < <(parse_todo_file)

    if [ ${#tasks[@]} -eq 0 ]; then
        print_error "No tasks found in todo.txt"
        exit 1
    fi

    print_header "FOUND ${#tasks[@]} TASKS"
    for i in "${!tasks[@]}"; do
        echo "  ${tasks[i]}. ${task_descriptions[i]}"
    done
    echo ""

    # Execute specific task or all tasks
    if [ -n "$target_task" ]; then
        # Execute single task
        local found=0
        for i in "${!tasks[@]}"; do
            if [ "${tasks[i]}" == "$target_task" ]; then
                execute_task "${tasks[i]}" "${task_descriptions[i]}"
                found=1
                break
            fi
        done

        if [ $found -eq 0 ]; then
            print_error "Task $target_task not found"
            exit 1
        fi
    else
        # Execute all tasks
        local failed_tasks=()

        for i in "${!tasks[@]}"; do
            if ! execute_task "${tasks[i]}" "${task_descriptions[i]}"; then
                failed_tasks+=("${tasks[i]}")
            fi
            echo ""  # Add spacing between tasks
        done

        # Report results
        if [ ${#failed_tasks[@]} -eq 0 ]; then
            print_success "All ${#tasks[@]} tasks completed successfully!"
        else
            print_error "${#failed_tasks[@]} tasks failed: ${failed_tasks[*]}"
            exit 1
        fi
    fi

    # Run final validation after task completion
    echo ""
    run_final_validation
}

# Show usage if help requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: $0 [task_number]"
    echo ""
    echo "Options:"
    echo "  task_number    Execute only the specified task (optional)"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "If no task_number is provided, all tasks will be executed."
    echo "Tests are run automatically after task completion."
    exit 0
fi

# Run main function
main "$@"