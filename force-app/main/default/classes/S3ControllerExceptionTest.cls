@IsTest
private class S3ControllerExceptionTest {

    @IsTest
    static void testExceptionWithMessage() {
        String msg = 'Test error message';
        try {
            throw new S3ControllerException(msg);
        } catch (S3ControllerException ex) {
            System.assertEquals(msg, ex.getMessage(), 'Exception message should match');
        }
    }

    @IsTest
    static void testExceptionWithCause() {
        Exception cause = new DmlException('root cause');
        try {
            throw new S3ControllerException('wrapper', cause);
        } catch (S3ControllerException ex) {
            System.assertEquals('wrapper', ex.getMessage());
            System.assertNotEquals(null, ex.getCause(), 'Cause should be set');
        }
    }
}