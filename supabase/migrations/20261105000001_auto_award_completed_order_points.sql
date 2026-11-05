CREATE OR REPLACE FUNCTION public.award_completed_order_membership_points(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_member public.customer_memberships%ROWTYPE;
  v_points INTEGER;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND OR v_order.status <> 'selesai' THEN
    RETURN;
  END IF;

  SELECT * INTO v_member
  FROM public.customer_memberships
  WHERE cafe_id = v_order.cafe_id
    AND lower(btrim(name)) = lower(btrim(v_order.customer_name));
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.membership_point_transactions
    WHERE member_id = v_member.id AND order_id = v_order.id
  ) THEN
    RETURN;
  END IF;

  v_points := floor(v_order.total / 1000)::INTEGER * 10;
  UPDATE public.customer_memberships
  SET points = points + v_points
  WHERE id = v_member.id;

  INSERT INTO public.membership_point_transactions(member_id, order_id, points, description)
  VALUES (v_member.id, v_order.id, v_points, 'Poin pesanan ' || v_order.public_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.award_points_when_order_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'selesai' AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.award_completed_order_membership_points(NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS award_completed_order_membership_points_trigger ON public.orders;
CREATE TRIGGER award_completed_order_membership_points_trigger
AFTER UPDATE OF status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.award_points_when_order_completed();

DO $$
DECLARE completed_order public.orders%ROWTYPE;
BEGIN
  FOR completed_order IN
    SELECT * FROM public.orders WHERE status = 'selesai'
  LOOP
    PERFORM public.award_completed_order_membership_points(completed_order.id);
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.award_completed_order_membership_points(UUID) FROM PUBLIC, anon, authenticated;
