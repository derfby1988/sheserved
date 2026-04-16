-- SQL Function for safely acquiring locks on donation transactions
-- Prevents race conditions during Escrow Release or Refunds
-- Use this instead of updating the status directly in Application Code

CREATE OR REPLACE FUNCTION process_escrow_transfer(p_transaction_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    -- ล็อก Row ทันที และป้องกันการอ่านข้อมูลเก่า (Pessimistic Locking)
    SELECT status INTO v_status 
    FROM donation_transactions 
    WHERE id = p_transaction_id 
    FOR UPDATE NOWAIT; -- ถ้าติด Lock อยู่จะ Throw error ทันที ไม่รอ

    IF v_status != 'in_escrow' THEN
        -- ถ้าสถานะไม่ใช่ in_escrow แสดงว่าโดน process ไปแล้ว (เช่น กำลัง refund)
        RETURN FALSE;
    END IF;

    -- เปลี่ยนสถานะเป็นชั่วคราว (Lock status at application level)
    UPDATE donation_transactions 
    SET status = 'processing_transfer', updated_at = NOW() 
    WHERE id = p_transaction_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
