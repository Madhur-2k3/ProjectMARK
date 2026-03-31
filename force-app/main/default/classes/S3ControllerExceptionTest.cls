/**
 * @description Tests for S3ControllerException custom exception class.
 */
@IsTest
private class S3ControllerExceptionTest {

    @IsTest
    static void testExceptionWithMessage() {

        String myMessageStr = 'Test error message';

        try {
            throw new S3ControllerException(myMessageStr);
        } catch (S3ControllerException myException) {
            System.assertEquals(myMessageStr, myException.getMessage(), 'Exception message should match');
        }
    }

    @IsTest
    static void testExceptionWithCause() {

        Exception myCauseException = new DmlException('root cause');

        try {
            throw new S3ControllerException('wrapper', myCauseException);
        } catch (S3ControllerException myException) {
            System.assertEquals('wrapper', myException.getMessage());
            System.assertNotEquals(null, myException.getCause(), 'Cause should be set');
        }
    }
}