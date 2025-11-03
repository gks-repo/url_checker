#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -t, --target FILE    (required)"
    echo "  -o, --output FILE    (optional)"
    echo "  -h, --help           Show this help message"
}

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to get human-readable curl error message
get_curl_error() {
    local error_code=$1
    case $error_code in
        6) echo "DNS_RESOLUTION_FAILED" ;;
        7) echo "CONNECTION_FAILED" ;;
        28) echo "TIMEOUT" ;;
        35) echo "SSL_CONNECT_ERROR" ;;
        60) echo "SSL_CERTIFICATE_ERROR" ;;
        *) echo "ERROR ($error_code)" ;;
    esac
}

# Function to colorize output
colorize_output() {
    local response="$1"
    local text="$2"
    
    case "$response" in
        200)
            echo -e "${GREEN}${text}${NC}"
            ;;
        404|TIMEOUT|DNS_RESOLUTION_FAILED|CONNECTION_FAILED)
            echo -e "${RED}${text}${NC}"
            ;;
        *)
            echo -e "${YELLOW}${text}${NC}"
            ;;
    esac
}

# Initialize variables
DOMAINS_FILE=""
OUTPUT_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--target)
            DOMAINS_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check required parameters
if [ -z "$DOMAINS_FILE" ]; then
    echo "❌ No domains file specified!"
    show_help
    exit 1
fi

# Check if domains file exists
if [ ! -f "$DOMAINS_FILE" ]; then
    echo "❌ File $DOMAINS_FILE not found!"
    exit 1
fi

# Check write permissions for output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    # Create/clear output file
    > "$OUTPUT_FILE"
fi

echo "🔍 Checking domains from file: $DOMAINS_FILE"
if [ -n "$OUTPUT_FILE" ]; then
    echo "💾 Results will be saved to: $OUTPUT_FILE"
fi
echo "================================================"

# Initialize counters
http_200_count=0
total_checked=0

while IFS= read -r domain; do
    if [ -n "$domain" ]; then
        # Skip comments and empty lines
        if [[ "$domain" =~ ^[[:space:]]*# ]] || [[ "$domain" =~ ^[[:space:]]*$ ]]; then
            continue
        fi
        
        # Remove extra spaces
        domain=$(echo "$domain" | xargs)
        
        echo -n "📍 $domain: "
        
        # Get HTTP response code
        http_response=$(curl -I -s -m 10 -w "%{http_code}" "https://$domain" -o /dev/null 2>/dev/null)
        curl_exit_code=$?
        
        result_text=""
        display_text=""
        file_text=""
        
        if [ $curl_exit_code -eq 0 ]; then
            result_text="HTTP $http_response"
            display_text="✅ $result_text"
            file_text="$domain: $result_text"
            
            # Count HTTP 200 responses
            if [ "$http_response" = "200" ]; then
                ((http_200_count++))
            fi
        elif [ $curl_exit_code -eq 28 ]; then
            result_text="TIMEOUT"
            display_text="⏰ $result_text"
            file_text="$domain: $result_text"
        else
            # Try HTTP if HTTPS failed
            http_response=$(curl -I -s -m 10 -w "%{http_code}" "http://$domain" -o /dev/null 2>/dev/null)
            curl_exit_code=$?
            
            if [ $curl_exit_code -eq 0 ]; then
                result_text="HTTP $http_response"
                display_text="✅ $result_text"
                file_text="$domain: $result_text"
                
                # Count HTTP 200 responses
                if [ "$http_response" = "200" ]; then
                    ((http_200_count++))
                fi
            elif [ $curl_exit_code -eq 28 ]; then
                result_text="TIMEOUT"
                display_text="⏰ $result_text"
                file_text="$domain: $result_text"
            else
                # Use human-readable error messages
                error_message=$(get_curl_error $curl_exit_code)
                result_text="$error_message"
                display_text="❌ $error_message"
                file_text="$domain: $error_message"
            fi
        fi
        
        # Total checked counter
        ((total_checked++))
        
        # Colorize terminal output based on response
        if [ $curl_exit_code -eq 0 ]; then
            colorize_output "$http_response" "$display_text"
        else
            colorize_output "$result_text" "$display_text"
        fi
        
        # Write to output file if specified
        if [ -n "$OUTPUT_FILE" ]; then
            echo "$file_text" >> "$OUTPUT_FILE"
        fi
        
        # Small delay between requests
        sleep 0.5
    fi
done < "$DOMAINS_FILE"

echo "================================================"

# Display summary
echo "✅ Successful: $http_200_count"
echo "📋 Total checked: $total_checked"

# Show output file path if specified
if [ -n "$OUTPUT_FILE" ]; then
    echo "💾 Results saved to: $OUTPUT_FILE"
fi
