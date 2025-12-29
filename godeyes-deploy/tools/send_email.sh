#!/bin/bash

##############################################################
################ Cần cấu hình thông tin để gửi mail ##########
##############################################################
export SENDER_EMAIL="chuongthanh0410@gmail.com"
export SENDER_PASSWORD="kgiqqxrkqljbmcon"
export RECIPIENT_EMAIL="chuongthanh0410@gmail.com"
export RECIPIENT_EMAIL_CC=""
export SMTP_SERVER="smtp.gmail.com"
export SMTP_PORT="587"

##############################################################
#################### Script gửi email thông báo ##############
##############################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Email configuration
SMTP_SERVER="${SMTP_SERVER:-smtp.gmail.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SENDER_EMAIL="${SENDER_EMAIL:-your-email@gmail.com}"
SENDER_PASSWORD="${SENDER_PASSWORD:-your-app-password}"
RECIPIENT_EMAIL="${RECIPIENT_EMAIL:-recipient@example.com}"
RECIPIENT_EMAIL_CC="${RECIPIENT_EMAIL_CC:-}"

# Info log function
info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC}  $1 "
}

# Debug log function
debug() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${CYAN} $1 ${NC}"
}

# Warning log function
warn() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW} $1 ${NC}"
}

# Error log function
error() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${RED} $1 ${NC}"
}

# Success log function
success() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${GREEN} $1 ${NC}"
}

# Check configuration
check_configuration() {
    info "Checking email configuration..."

    if [ "$SENDER_EMAIL" = "your-email@gmail.com" ]; then
        error "SENDER_EMAIL not configured. Please set environment variable"
        return 1
    fi

    if [ "$SENDER_PASSWORD" = "your-app-password" ]; then
        error "SENDER_PASSWORD not configured. Please set environment variable"
        return 1
    fi

    if [ "$RECIPIENT_EMAIL" = "recipient@example.com" ]; then
        error "RECIPIENT_EMAIL not configured. Please set environment variable"
        return 1
    fi

    success "Email configuration is valid"
    return 0
}

# Function to send email using mailutils
send_email_mailutils() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    info "Sending email to $recipient..."

    # Create email content
    {
        echo "From: $SENDER_EMAIL"
        echo "To: $recipient"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"

        echo "$body"
    } | msmtp -a default "$recipient"

    if [ $? -eq 0 ]; then
        success "Email sent successfully"
        return 0
    else
        error "Error sending email"
        return 1
    fi
}

# Function to send email using ssmtp
send_email_ssmtp() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    info "Sending email to $recipient..."

    # Create email content
    {
        echo "From: $SENDER_EMAIL"
        echo "To: $recipient"
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"

        echo "$body"
    } | ssmtp "$recipient"

    if [ $? -eq 0 ]; then
        success "Email sent successfully"
        return 0
    else
        error "Error sending email"
        return 1
    fi
}

# Function to send email using curl (SMTP)
send_email_curl() {
    local recipient="$1"
    local subject="$2"
    local body="$3"

    info "Sending email to $recipient ..."

    # Create temporary email file
    local email_file=$(mktemp)
    {
        echo "From: $SENDER_EMAIL"
        echo "To: $recipient"
        if [ -n "$RECIPIENT_EMAIL_CC" ]; then
            echo "Cc: $RECIPIENT_EMAIL_CC"
        fi
        echo "Subject: $subject"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/html; charset=UTF-8"

        echo "$body"
    } > "$email_file"

    # Send email with CC support
    curl --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
    --ssl-reqd \
    --mail-from "$SENDER_EMAIL" \
    --mail-rcpt "$recipient" \
    $([ -n "$RECIPIENT_EMAIL_CC" ] && echo "--mail-rcpt $RECIPIENT_EMAIL_CC") \
    --user "$SENDER_EMAIL:$SENDER_PASSWORD" \
    --upload-file "$email_file" \
    --silent --show-error

    local result=$?
    rm -f "$email_file"

    if [ $result -eq 0 ]; then
        success "Email sent successfully"
        return 0
    else
        error "Error sending email"
        return 1
    fi
}

# Function to send error alert email
send_error_alert() {
    local error_message="$1"
    local subject="[ALERT] GodEyes Edge - Error"

    local body="<html>
    <body style='font-family: Arial, sans-serif;'>
    <h2 style='color: #d9534f;'>GodEyes Edge Error Alert</h2>
    <p><strong>Time:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>Error message:</strong></p>
    <pre style='background-color: #f5f5f5; padding: 10px; border-radius: 5px;'>$error_message</pre>
    <hr>
    <p><em>This email was sent automatically from GodEyes Edge Monitor system</em></p>
    </body>
    </html>"

    send_email_curl "$RECIPIENT_EMAIL" "$subject" "$body"
}

# Function to send success update notification
send_success_notification() {
    local message="$1"
    local subject="[SUCCESS] GodEyes Edge - Update Successful"

    local body="<html>
    <body style='font-family: Arial, sans-serif;'>
    <h2 style='color: #5cb85c;'>Update Successful</h2>
    <p><strong>Time:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>Message:</strong></p>
    <pre style='background-color: #f5f5f5; padding: 10px; border-radius: 5px;'>$message</pre>
    <hr>
    <p><em>This email was sent automatically from GodEyes Edge Monitor system</em></p>
    </body>
    </html>"

    send_email_curl "$RECIPIENT_EMAIL" "$subject" "$body"
}

# Function to send image update required notification
send_update_required() {
    local local_id="$1"
    local remote_id="$2"
    local message="$3"
    local subject="[UPDATE] GodEyes Edge - Image Update Required"

    local body="<html>
    <body style='font-family: Arial, sans-serif;'>
    <h2 style='color: #f0ad4e;'>Image Update Required</h2>
    <p><strong>Time:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>Details:</strong></p>
    <ul>
    <li><strong>Current image:</strong> chuongthanh0410/godeyes:godeyes-edge-latest</li>
    <li><strong>Local ID:</strong> $local_id</li>
    <li><strong>Remote ID:</strong> $remote_id</li>
    </ul>
    <p>The system will automatically update to the latest image.</p>
    <hr>
    <p><em>This email was sent automatically from GodEyes Edge Monitor system</em></p>
    </body>
    </html>"

    send_email_curl "$RECIPIENT_EMAIL" "$subject" "$body"
}

# Function to send startup notification
send_startup_notification() {
    local ip_output=$(ip a)
    local subject="[STARTUP] GodEyes Edge - Start Up Success"

    local body="<html>
    <body style='font-family: Arial, sans-serif;'>
    <h2 style='color: #5cb85c;'>GodEyes Edge Start Up Success</h2>
    <p><strong>Time:</strong> $(date '+%Y-%m-%d %H:%M:%S')</p>
    <p><strong>Network Information:</strong></p>
    <pre style='background-color: #f5f5f5; padding: 10px; border-radius: 5px; word-wrap: break-word;'>$ip_output</pre>
    <hr>
    <p><em>This email was sent automatically from GodEyes Edge Monitor system</em></p>
    </body>
    </html>"

    send_email_curl "$RECIPIENT_EMAIL" "$subject" "$body"
}

# Main function
main() {

    # Check configuration
    check_configuration || exit 1

    # If parameters provided, send custom email
    if [ $# -gt 0 ]; then
        case "$1" in
            error)
                send_error_alert "$2"
            ;;
            success)
                send_success_notification "$2"
            ;;
            update)
                send_update_required "$2" "$3"
            ;;
            startup)
                send_startup_notification
            ;;
            custom)
                send_email_curl "$2" "$3" "$4"
            ;;
            *)
                error "Unknown command: $1"
                echo "Usage:"
                echo "  $0 error \"<error message>\""
                echo "  $0 success \"<success message>\""
                echo "  $0 update \"<local id>\" \"<remote id>\""
                echo "  $0 startup"
                echo "  $0 custom \"<email>\" \"<subject>\" \"<body>\""
                exit 1
            ;;
        esac
    else
        error "Please provide email type to send"
        echo "Usage:"
        echo "  $0 error \"<error message>\""
        echo "  $0 success \"<success message>\""
        echo "  $0 update \"<local id>\" \"<remote id>\""
        echo "  $0 startup"
        echo "  $0 custom \"<email>\" \"<subject>\" \"<body>\""
        exit 1
    fi
}

main "$@"
