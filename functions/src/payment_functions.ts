// payment_functions.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';
import Stripe from 'stripe';
import { defineSecret } from 'firebase-functions/params';

const stripeTestKey = defineSecret("STRIPE_TEST_KEY");

export const createPaymentIntent = onCall(
  { secrets: [stripeTestKey] },
  async (request) => {
    const stripe = new Stripe(stripeTestKey.value(), { apiVersion: "2025-02-24.acacia" });
    const { amount, currency } = request.data;
    try {
      const paymentIntent = await stripe.paymentIntents.create({
        amount,
        currency,
      });
  
      return { clientSecret: paymentIntent.client_secret };
    } catch (error) {
      let errorMessage = 'An unknown error occurred';
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      logger.error('Error creating payment intent:', error);
      throw new HttpsError('internal', errorMessage);
    }
  }
);

export const verifyPaymentStatus = onCall(
  { secrets: [stripeTestKey] },
  async (request) => {
    const stripe = new Stripe(stripeTestKey.value(), { apiVersion: "2025-02-24.acacia" });
    const { clientSecret } = request.data;
    if (!clientSecret) {
      throw new HttpsError('invalid-argument', 'Missing clientSecret');
    }
    // Extract the PaymentIntent ID from the clientSecret.
    // The clientSecret is in the format "pi_xxx_secret_yyy", so splitting it gives the ID.
    const parts = clientSecret.split('_secret_');
    if (parts.length < 2) {
      throw new HttpsError('invalid-argument', 'Invalid clientSecret format.');
    }
    const paymentIntentId = parts[0];
    
    try {
      // Retrieve the PaymentIntent from Stripe.
      const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);
      // Return the current status (e.g. 'succeeded', 'requires_payment_method', etc.).
      return { status: paymentIntent.status };
    } catch (error) {
      let errorMessage = 'An unknown error occurred';
      if (error instanceof Error) {
        errorMessage = error.message;
      }
      logger.error('Error verifying payment status:', error);
      throw new HttpsError('internal', errorMessage);
    }
  }
);