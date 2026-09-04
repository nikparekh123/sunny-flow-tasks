-- ⚠ THE BUFFER WAS RACING IBKR, NOT WAITING FOR IT.
-- A leg expiring Fri 28 Aug had IBKR's own lifecycle close (A / Ep) delivered
-- on Tue 1 Sep, four calendar days later because of the weekend. At
-- buffer_days = 2 this function fired first, on Mon 31 Aug, and nine legs
-- ended up closed TWICE: once synthetically, once for real. closed > opened
-- makes the residual negative, which every downstream netting reads as a
-- phantom LONG position.
--
-- Six days clears a Friday expiry plus a weekend plus a holiday, so IBKR gets
-- first refusal on every leg it will report. This function remains the
-- backstop for legs IBKR will never report (manual entries), and still only
-- fires where a positive residual is left.
CREATE OR REPLACE FUNCTION public.close_expired_option_legs(buffer_days integer DEFAULT 6)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE inserted integer;
BEGIN
  WITH keyagg AS (
    SELECT ticker, option_type, direction, strike, expiry,
           SUM(contracts) FILTER (WHERE action='open')  AS opened,
           COALESCE(SUM(contracts) FILTER (WHERE action='close'),0) AS closed
    FROM public.option_trades WHERE voided_at IS NULL
    GROUP BY ticker, option_type, direction, strike, expiry),
  residuals AS (
    SELECT ticker, option_type, direction, strike, expiry, opened-closed AS residual
    FROM keyagg
    WHERE expiry < current_date - make_interval(days => buffer_days) AND opened-closed > 0),
  ins AS (
    INSERT INTO public.option_trades
      (ticker, trade_date, action, option_type, direction, contracts, strike, premium, expiry, source, note)
    SELECT ticker, expiry, 'close', option_type, direction, residual, strike, 0, expiry, 'expiry', 'auto-closed at expiry'
    FROM residuals RETURNING 1)
  SELECT count(*) INTO inserted FROM ins;
  RETURN inserted;
END $function$;

-- The cron passed 2 explicitly, which overrode the default.
SELECT cron.schedule('close-expired-options-daily', '0 10 * * *',
                     'select public.close_expired_option_legs(6);');
