import json
import os
import smtplib
import threading
import urllib.request
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Optional
from ..core.config import settings


def _safe_print(text: str):
    """Safely print text on any terminal without Windows cp1252 crashes."""
    try:
        print(text)
    except UnicodeEncodeError:
        try:
            print(text.encode("ascii", errors="replace").decode("ascii"))
        except Exception:
            pass


def _send_via_resend(to_email: str, subject: str, html_content: str, text_content: str) -> bool:
    """Delivers email via Resend HTTPS API (Port 443, never blocked by cloud hosts)."""
    api_key = (settings.RESEND_API_KEY or "").strip()
    if not api_key:
        return False
    try:
        import httpx
        from_email = (settings.SMTP_FROM_EMAIL or "TwoOfUs <onboarding@resend.dev>").strip()
        payload = {
            "from": from_email,
            "to": [to_email],
            "subject": subject,
            "html": html_content,
            "text": text_content,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "resend-python/2.0.0",
        }
        with httpx.Client(timeout=15.0) as client:
            resp = client.post("https://api.resend.com/emails", json=payload, headers=headers)
            if resp.status_code in (200, 201):
                _safe_print(f"[RESEND EMAIL DELIVERED] Successfully sent '{subject}' to {to_email} via Resend HTTPS API")
                return True
            else:
                _safe_print(f"[RESEND API ERROR] Status {resp.status_code}: {resp.text}")
                return False
    except Exception as e:
        _safe_print(f"[RESEND API EXCEPTION] {e}")
        return False


def _send_via_brevo(to_email: str, subject: str, html_content: str, text_content: str) -> bool:
    """Delivers email via Brevo HTTPS API (Port 443, free 300 emails/day)."""
    api_key = (settings.BREVO_API_KEY or "").strip()
    if not api_key:
        return False
    try:
        import httpx
        sender_email = (settings.SMTP_USER or "twoofus.app@gmail.com").strip()
        payload = {
            "sender": {"name": "TwoOfUs", "email": sender_email},
            "to": [{"email": to_email}],
            "subject": subject,
            "htmlContent": html_content,
            "textContent": text_content
        }
        headers = {
            "api-key": api_key,
            "Content-Type": "application/json",
            "User-Agent": "TwoOfUs-App/1.0",
        }
        with httpx.Client(timeout=15.0) as client:
            resp = client.post("https://api.brevo.com/v3/smtp/email", json=payload, headers=headers)
            if resp.status_code in (200, 201):
                _safe_print(f"[BREVO EMAIL DELIVERED] Successfully sent '{subject}' to {to_email} via Brevo HTTPS API")
                return True
            else:
                _safe_print(f"[BREVO API ERROR] Status {resp.status_code}: {resp.text}")
                return False
    except Exception as e:
        _safe_print(f"[BREVO API EXCEPTION] {e}")
        return False


def _send_via_sendgrid(to_email: str, subject: str, html_content: str, text_content: str) -> bool:
    """Delivers email via SendGrid HTTPS API (Port 443)."""
    api_key = (settings.SENDGRID_API_KEY or "").strip()
    if not api_key:
        return False
    try:
        import httpx
        sender_email = (settings.SMTP_USER or "twoofus.app@gmail.com").strip()
        payload = {
            "personalizations": [{"to": [{"email": to_email}]}],
            "from": {"email": sender_email, "name": "TwoOfUs"},
            "subject": subject,
            "content": [
                {"type": "text/plain", "value": text_content},
                {"type": "text/html", "value": html_content}
            ]
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "User-Agent": "TwoOfUs-App/1.0",
        }
        with httpx.Client(timeout=15.0) as client:
            resp = client.post("https://api.sendgrid.com/v3/mail/send", json=payload, headers=headers)
            if resp.status_code in (200, 202):
                _safe_print(f"[SENDGRID EMAIL DELIVERED] Successfully sent '{subject}' to {to_email} via SendGrid HTTPS API")
                return True
            else:
                _safe_print(f"[SENDGRID API ERROR] Status {resp.status_code}: {resp.text}")
                return False
    except Exception as e:
        _safe_print(f"[SENDGRID API EXCEPTION] {e}")
        return False


def _send_smtp_message(to_email: str, subject: str, html_content: str, text_content: str) -> bool:
    """Internal delivery dispatcher: tries HTTPS APIs (Resend, Brevo, SendGrid) first, then SMTP."""
    # 1. Try cloud HTTPS APIs first (these work on Render where outbound SMTP is blocked)
    if settings.RESEND_API_KEY:
        if _send_via_resend(to_email, subject, html_content, text_content):
            return True

    if settings.BREVO_API_KEY:
        if _send_via_brevo(to_email, subject, html_content, text_content):
            return True

    if settings.SENDGRID_API_KEY:
        if _send_via_sendgrid(to_email, subject, html_content, text_content):
            return True

    # 2. Try SMTP
    smtp_host = settings.SMTP_HOST
    smtp_port = settings.SMTP_PORT
    smtp_user = settings.SMTP_USER
    smtp_password = settings.SMTP_PASSWORD
    from_email = settings.SMTP_FROM_EMAIL or (smtp_user if smtp_user else "TwoOfUs <noreply@twoofus.app>")

    # If no SMTP configured, log clearly in the server console with full email content
    if not smtp_host or not smtp_user:
        _safe_print("\n" + "=" * 55)
        _safe_print(" [EMAIL DISPATCH - LOCAL SIMULATION]")
        _safe_print(f" To: {to_email}")
        _safe_print(f" Subject: {subject}")
        _safe_print("-" * 55)
        _safe_print(text_content.strip())
        _safe_print("=" * 55)
        _safe_print(" Tip: On Render/Cloud hosts, outbound SMTP is blocked.")
        _safe_print(" Set RESEND_API_KEY or BREVO_API_KEY in Render Environment Variables.")
        _safe_print("=" * 55 + "\n")
        return True

    modes_to_try = []
    is_ssl = settings.SMTP_USE_SSL or smtp_port == 465
    modes_to_try.append((smtp_port, is_ssl))
    alt_port = 465 if smtp_port == 587 else 587
    alt_ssl = (alt_port == 465)
    modes_to_try.append((alt_port, alt_ssl))

    for port, use_ssl in modes_to_try:
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = from_email
            msg["To"] = to_email

            part1 = MIMEText(text_content, "plain", "utf-8")
            part2 = MIMEText(html_content, "html", "utf-8")
            msg.attach(part1)
            msg.attach(part2)

            if use_ssl:
                server = smtplib.SMTP_SSL(smtp_host, port, timeout=12)
            else:
                server = smtplib.SMTP(smtp_host, port, timeout=12)
                server.starttls()

            if smtp_user and smtp_password:
                server.login(smtp_user, smtp_password)

            server.sendmail(from_email, [to_email], msg.as_string())
            server.quit()
            _safe_print(f"[EMAIL DELIVERED] Successfully sent '{subject}' to {to_email} (SMTP port {port})")
            return True
        except Exception as e:
            _safe_print(f"[EMAIL ATTEMPT FAILED] (port {port}): {e}")

    _safe_print(f"[EMAIL DELIVERY FAILED] Could not send email to {to_email} via SMTP (outbound ports blocked on cloud host).")
    _safe_print("\n" + "-" * 55)
    _safe_print(f" [FALLBACK CODE LOG] To: {to_email} | Subject: {subject}")
    _safe_print(text_content.strip())
    _safe_print("-" * 55 + "\n")
    return False


def send_email_async(to_email: str, subject: str, html_content: str, text_content: str):
    """Sends an email in a background thread to prevent blocking API responses."""
    thread = threading.Thread(
        target=_send_smtp_message,
        args=(to_email, subject, html_content, text_content),
        daemon=True
    )
    thread.start()


def send_password_reset_email(to_email: str, username: str, code: str, run_async: bool = True) -> bool:
    """Sends a password reset code email with TwoOfUs branding."""
    subject = "TwoOfUs - Password Reset Code"
    
    text_content = f"""
Hello {username},

You requested a password reset for your TwoOfUs account.

Your 6-digit verification code is: {code}

This code will expire in 15 minutes. If you did not make this request, you can safely ignore this email — your account remains secure.

Warmly,
The TwoOfUs Team ❤️
"""

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0d0614; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #f0e6f6;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #0d0614; width: 100%; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width: 520px; background: linear-gradient(145deg, #1f0b2f, #150622); border-radius: 24px; border: 1px solid rgba(255, 64, 129, 0.25); box-shadow: 0 16px 40px rgba(0, 0, 0, 0.6); overflow: hidden;">
          
          <!-- Header -->
          <tr>
            <td style="padding: 36px 36px 20px 36px; text-align: center;">
              <div style="font-size: 40px; line-height: 1; margin-bottom: 8px;">❤️</div>
              <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #ffffff; letter-spacing: 0.5px;">TwoOfUs</h1>
              <p style="margin: 6px 0 0 0; font-size: 13px; color: #ff80ab; font-weight: 500;">Private • Secure • End-to-End Encrypted</p>
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding: 0 36px;">
              <div style="height: 1px; background: linear-gradient(90deg, transparent, rgba(255, 64, 129, 0.4), transparent);"></div>
            </td>
          </tr>

          <!-- Body Content -->
          <tr>
            <td style="padding: 28px 36px 20px 36px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-size: 18px; font-weight: 600; color: #ffffff;">Password Reset Request</h2>
              <p style="margin: 0 0 24px 0; font-size: 14px; line-height: 1.5; color: #d1c4e9;">
                Hi <strong>{username}</strong>, we received a request to reset your password. Use the verification code below to complete your reset:
              </p>

              <!-- Code Box -->
              <div style="display: inline-block; padding: 18px 36px; background: rgba(0, 0, 0, 0.45); border: 2px dashed #ff4081; border-radius: 16px; margin-bottom: 24px;">
                <span style="font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 800; letter-spacing: 12px; color: #ffd54f; text-shadow: 0 0 12px rgba(255, 213, 79, 0.4);">{code}</span>
              </div>

              <!-- Expiry Alert -->
              <p style="margin: 0 0 20px 0; font-size: 13px; color: #ffab40;">
                ⏱️ This code expires in <strong>15 minutes</strong>.
              </p>

              <p style="margin: 0; font-size: 12px; line-height: 1.4; color: #9575cd;">
                If you did not request this password reset, please ignore this email or update your password if you suspect unauthorized access.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 20px 36px 30px 36px; text-align: center; background-color: rgba(0, 0, 0, 0.2);">
              <p style="margin: 0; font-size: 12px; color: #7e57c2;">
                Sent with ❤️ from TwoOfUs &bull; Your private shared world
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    if run_async:
        send_email_async(to_email, subject, html_content, text_content)
        return True
    return _send_smtp_message(to_email, subject, html_content, text_content)


def send_2fa_otp_email(to_email: str, username: str, code: str, run_async: bool = True) -> bool:
    """Sends a 2FA login verification code email."""
    subject = "TwoOfUs - 2FA Verification Code"
    
    text_content = f"""
Hello {username},

Your TwoOfUs Two-Factor Authentication (2FA) verification code is: {code}

This code is valid for 10 minutes. If you did not initiate this login attempt, please change your password immediately.

Warmly,
The TwoOfUs Team ❤️
"""

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{subject}</title>
</head>
<body style="margin: 0; padding: 0; background-color: #0d0614; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #f0e6f6;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #0d0614; width: 100%; padding: 40px 15px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width: 520px; background: linear-gradient(145deg, #1f0b2f, #150622); border-radius: 24px; border: 1px solid rgba(64, 196, 255, 0.25); box-shadow: 0 16px 40px rgba(0, 0, 0, 0.6); overflow: hidden;">
          
          <!-- Header -->
          <tr>
            <td style="padding: 36px 36px 20px 36px; text-align: center;">
              <div style="font-size: 40px; line-height: 1; margin-bottom: 8px;">🛡️</div>
              <h1 style="margin: 0; font-size: 24px; font-weight: 700; color: #ffffff; letter-spacing: 0.5px;">TwoOfUs</h1>
              <p style="margin: 6px 0 0 0; font-size: 13px; color: #40c4ff; font-weight: 500;">Two-Factor Security Verification</p>
            </td>
          </tr>

          <!-- Divider -->
          <tr>
            <td style="padding: 0 36px;">
              <div style="height: 1px; background: linear-gradient(90deg, transparent, rgba(64, 196, 255, 0.4), transparent);"></div>
            </td>
          </tr>

          <!-- Body Content -->
          <tr>
            <td style="padding: 28px 36px 20px 36px; text-align: center;">
              <h2 style="margin: 0 0 12px 0; font-size: 18px; font-weight: 600; color: #ffffff;">Your Login Verification Code</h2>
              <p style="margin: 0 0 24px 0; font-size: 14px; line-height: 1.5; color: #d1c4e9;">
                Hi <strong>{username}</strong>, enter the code below to complete your login to TwoOfUs:
              </p>

              <!-- Code Box -->
              <div style="display: inline-block; padding: 18px 36px; background: rgba(0, 0, 0, 0.45); border: 2px dashed #40c4ff; border-radius: 16px; margin-bottom: 24px;">
                <span style="font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 800; letter-spacing: 12px; color: #69f0ae; text-shadow: 0 0 12px rgba(105, 240, 174, 0.4);">{code}</span>
              </div>

              <!-- Expiry Alert -->
              <p style="margin: 0 0 20px 0; font-size: 13px; color: #ffab40;">
                ⏱️ This code expires in <strong>10 minutes</strong>.
              </p>

              <p style="margin: 0; font-size: 12px; line-height: 1.4; color: #9575cd;">
                Never share this code with anyone. If you didn't attempt to sign in, secure your account right away.
              </p>
            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="padding: 20px 36px 30px 36px; text-align: center; background-color: rgba(0, 0, 0, 0.2);">
              <p style="margin: 0; font-size: 12px; color: #7e57c2;">
                Sent with 🛡️ from TwoOfUs &bull; Your private shared world
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"""

    if run_async:
        send_email_async(to_email, subject, html_content, text_content)
        return True
    return _send_smtp_message(to_email, subject, html_content, text_content)
