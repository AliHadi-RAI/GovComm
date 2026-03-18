const crypto = require('crypto');
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'smtp.gmail.com',
    port: process.env.SMTP_PORT || 587,
    secure: false, 
    auth: {
        user: process.env.EMAIL_USER, 
        pass: process.env.EMAIL_PASS  
    }
});


function generateOTP() {
    return crypto.randomInt(100000, 1000000).toString();
}

async function sendOTPEmail(email, otp) {
    const mailOptions = {
        from: `"GovComm Security" <${process.env.EMAIL_USER}>`,
        to: email,
        subject: 'Your GovComm Verification Code',
        text: `Your verification code is: ${otp}. This code will expire in 5 minutes.`,
        html: `
            <div style="font-family: Arial, sans-serif; padding: 20px; border: 1px solid #eee;">
                <h2 style="color: #333;">GovComm Verification</h2>
                <p>Please use the following code to complete your authentication:</p>
                <div style="font-size: 24px; font-weight: bold; color: #007bff; letter-spacing: 5px; padding: 10px 0;">
                    ${otp}
                </div>
                <p style="color: #666; font-size: 12px;">If you did not request this code, please ignore this email.</p>
            </div>
        `
    };

    try {
        await transporter.sendMail(mailOptions);
        console.log(` OTP Email sent successfully to: ${email}`);
    } catch (error) {
        console.error(' Error sending OTP email:', error);
        throw new Error('Failed to send verification email');
    }
}

function verifyOTP(storedSecret, inputToken) {
    if (!storedSecret || !inputToken) {
        return false;
    }
    
    const cleanStored = String(storedSecret).trim();
    const cleanInput = String(inputToken).trim();

    if (cleanStored.length !== cleanInput.length) return false;

    return crypto.timingSafeEqual(
        Buffer.from(cleanStored), 
        Buffer.from(cleanInput)
    );
}

module.exports = { generateOTP, verifyOTP, sendOTPEmail };